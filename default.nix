{ pkgs ? import <nixpkgs> {}, lib ? pkgs.lib, stdenv ? pkgs.stdenv, zig ? pkgs.zig, static ? true, target }:

with lib;
with builtins;

# TODO: static == true && glibc target should result in evaluation error

let
  cross-system = systems.elaborate (
    if hasSuffix "mingw32" target then { config = target; libc = "msvcrt"; }
    else { config = target; }
  );

  zig-stdenv = let
    zig-target = let
      map-target = y: let
        kernel-map = {
          none = y: "${y.cpu.name}-freestanding-${y.abi.name}";
          linux = y: "${y.cpu.name}-linux-${y.abi.name}";
          darwin = y: "${y.cpu.name}-macos-gnu";
          windows = y: "${y.cpu.name}-windows-gnu";
          wasi = y: "${y.cpu.name}-wasi-musl";
        };
        cpu-map = {
          powerpc64 = y: removeSuffix "abi64" y;
          sparc64 = y: "sparcv9-${removePrefix "sparc64-" y}";
          armv5tel = y: "thumb-${removePrefix "armv5tel-" y}";
        };
      in cpu-map."${y.cpu.name}" or (_: _) (kernel-map."${y.kernel.name}" y);
    in map-target cross-system.parsed;

    # Bunch of overrides to make sure we don't ever start bootstrapping another cross-compiler
    overrides = self: super: let
      to-override-set = x: genAttrs x (x: null);
      llvmPackages = to-override-set [ "clang" "libclang" "lld" "llvm" "libllvm" "compiler-rt" "libunwind" "libstdcxx" "libcxx" "libcxxapi" "openmp" ];
      windows = to-override-set [ "mingw_w64" "mingw_w64_headers" "mingw_w64_pthreads" "mingwrt" "mingw_runtime" "w32api" "pthreads" "libgnurx" ];
      darwin = to-override-set [ "LibsystemCross" "libiconv" ];
    in (to-override-set [
      "gcc" "libgcc" "glibc" "bintools" "bintoolsNoLibc" "binutils" "binutilsNoLibc"
      "gccCrossStageStatic" "preLibcCrossHeaders" "glibcCross" "muslCross" "libcCross" "threadsCross"
    ]) // {
      inherit llvmPackages windows darwin;
      inherit (llvmPackages) clang libclang lld llvm libllvm libunwind libstdcxx libcxx libcxxapi openmp;
      gccForLibs = null; # also disables --gcc-toolchain passed to compiler
    };

    bintools = pkgs.bintoolsNoLibc;
    llvmtools = pkgs.llvmPackages.llvm;
    write-zig-wrapper = cmd: pkgs.writeShellScript "zig-${cmd}" ''${zig}/bin/zig ${cmd} "$@"'';
    symlinks = [
      { name = "bin/clang"; path = write-zig-wrapper "cc"; }
      { name = "bin/clang++"; path = write-zig-wrapper "c++"; }
      { name = "bin/ld"; path = write-zig-wrapper "cc"; }
      { name = "bin/ar"; path = write-zig-wrapper "ar"; }
      { name = "bin/ranlib"; path = write-zig-wrapper "ranlib"; }
      { name = "bin/dlltool"; path = write-zig-wrapper "dlltool"; }
      { name = "bin/lib"; path = write-zig-wrapper "lib"; }
      { name = "bin/windres"; path = "rc"; }
    ] ++ map (x: { name = "bin/${x}"; path = "${bintools}/bin/${x}"; }) [
      "c++filt"
    ] ++ map (x: { name = "bin/${x}"; path = "${llvmtools}/bin/llvm-${x}"; }) [
      "addr2line" "as" "dwarfdump" "lipo" "install-name-tool" "nm" "objcopy" "objdump" "rc" "readelf" "size" "strings" "strip"
    ] ++ map (x: { name = "bin/llvm-${x}"; path = "${llvmtools}/bin/llvm-${x}"; }) [
      "cat" "cov" "c-test" "cfi-verify" "bcanalyzer" "cvtres" "cxxdump" "cxxfilt" "cxxmap" "diff" "dis" "dwp" "elfabi" "rtdyld"
      "exegesis" "extract" "gsymutil" "ifs" "link" "lto" "lto2" "jitlink" "split" "stress" "symbolizer" "tblgen" "undname" "xray"
      "opt-report" "pdbutil" "profdata" "mc" "mca" "ml" "modextract" "mt" "readobj" "reduce"
    ];

    zig-toolchain = (pkgs.linkFarm "zig-toolchain" symlinks) // {
      inherit (pkgs.llvmPackages.libclang) version;
      pname = "zig-toolchain";
      isClang = true;
      libllvm.out = "";
    };

    cross0 = if pkgs.buildPlatform.config == target then pkgs else import pkgs.path {
      config.allowUnsupportedSystem = true;
      crossSystem = cross-system;
      localSystem.config = pkgs.buildPlatform.config;
      crossOverlays = [ overrides ];
    };

    static-stdenv-maybe = x: if static then cross0.makeStatic x else x;

    zig-stdenv0 = static-stdenv-maybe (cross0.overrideCC cross0.stdenv (cross0.wrapCCWith rec {
      inherit (pkgs) gnugrep coreutils;
      cc = zig-toolchain; libc = cc; libcxx = cc;
      bintools = cross0.wrapBintoolsWith { inherit libc gnugrep coreutils; bintools = zig-toolchain; };
      # XXX: -march and -mcpu are not compatible
      #      https://github.com/ziglang/zig/issues/4911
      extraBuildCommands = ''
        substituteInPlace $out/nix-support/add-local-cc-cflags-before.sh --replace "${target}" "${zig-target}"
        sed -i 's/\([^ ]\)-\([^ ]\)/\1_\2/g' $out/nix-support/cc-cflags-before || true
        sed -i 's/-arch [^ ]* *//g' $out/nix-support/cc-cflags || true
      '' + (optionalString (
        cross-system.parsed.cpu.name == "aarch64" || cross-system.parsed.cpu.name == "aarch64_be" ||
        cross-system.parsed.cpu.name == "armv5tel" || cross-system.parsed.cpu.name == "mipsel") ''
        # error: Unknown CPU: ...
        sed -i 's/-march[^ ]* *//g' $out/nix-support/cc-cflags-before || true
      '') + (optionalString (cross-system.parsed.cpu.name == "s390x") ''
        printf " -march=''${S390X_MARCH:-arch8}" >> $out/nix-support/cc-cflags-before
      '');
    }));

  # Aaand .. finally our final stdenv :)
  in zig-stdenv0.override {
    inherit overrides;
    # XXX: Zig doesn't support response file. Nixpkgs wants to use this for clang
    #      while zig cc is basically clang, it's still not 100% compatible.
    #      Probably should report this as a bug to zig upstream though.
    preHook = ''
      ${cross0.stdenv.preHook}
      export NIX_CC_USE_RESPONSE_FILE=0
      export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache-${target}"
      export ZIG_GLOBAL_CACHE_DIR="$ZIG_LOCAL_CACHE_DIR"
    '';
  };

  # Rust specific fixes, this lambda is exported so it can be used to wrap any rust toolchain
  wrapRustToolchain = rust-toolchain: let
    rust-config = {
      target = rec {
        name = target;
        cargo = stringAsChars (x: if x == "-" then "_" else x) (toUpper name);
        # FIXME: libcompiler_rt.a removal for rust is a ugly hack that I eventually want to get rid of
        #        https://github.com/ziglang/zig/issues/5320
        linker = pkgs.writeShellScript "cc-target" ''
          args=()
          for v in "$@"; do
            [[ "$v" == *self-contained/crt1.o ]] && continue
            [[ "$v" == *self-contained/crti.o ]] && continue
            [[ "$v" == *self-contained/crtn.o ]] && continue
            [[ "$v" == *self-contained/crtend.o ]] && continue
            [[ "$v" == *self-contained/crtbegin.o ]] && continue
            [[ "$v" == *self-contained/libc.a ]] && continue
            [[ "$v" == -lc ]] && continue
            args+=("$v")
          done
          export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache-${target}-rust"
          export ZIG_GLOBAL_CACHE_DIR="$ZIG_LOCAL_CACHE_DIR"
          if ! cc "''${args[@]}"; then
            find "$ZIG_LOCAL_CACHE_DIR" -name libcompiler_rt.a | while read -r f; do
              rm -f "$f"; touch "$f"
            done
            cc "''${args[@]}"
          fi
          '';
        flags = if static then "-C target-feature=+crt-static" else "";
      };
      host = rec {
        name = stdenv.buildPlatform.config;
        cargo = stringAsChars (x: if x == "-" then "_" else x) (toUpper name);
        # XXX: The fact darwin does not set libiconv linker path may be a bug
        #      darwin.cctools / codesign_allocate is a known issue
        #      ideally we could just set this to stdenv.cc though
        #      https://github.com/NixOS/nixpkgs/pull/148282
        linker = if stdenv.isDarwin then pkgs.writeShellScript "cc-host"
          ''PATH="${pkgs.darwin.cctools}/bin:$PATH" ${stdenv.cc}/bin/cc "$@" -L${pkgs.libiconv}/lib''
          else stdenv.cc;
      };
    };

    # XXX: wrap rustc instead?
    wrapped-cargo = pkgs.writeShellScript "wrapped-cargo" ''
      export CARGO_BUILD_TARGET=${rust-config.target.name}
      export CARGO_TARGET_${rust-config.host.cargo}_LINKER=${rust-config.host.linker}
      export CARGO_TARGET_${rust-config.target.cargo}_LINKER=${rust-config.target.linker}
      export CARGO_TARGET_${rust-config.target.cargo}_RUSTFLAGS="${rust-config.target.flags}"
      ${rust-toolchain}/bin/cargo "$@"
    '';
  in pkgs.symlinkJoin {
    name = "${rust-toolchain.name}-wrapped";
    paths = [ rust-toolchain ];
    postBuild = ''
      rm $out/bin/cargo
      ln -s ${wrapped-cargo} $out/bin/cargo
    '';
  };

  cross = (import pkgs.path {
    crossSystem = cross-system;
    localSystem.config = pkgs.buildPlatform.config;

    overlays = [(self: super: {
      rust = wrapRustToolchain super.rust;

      # cmake sucks at picking up the right compiler ...
      # probably darwin only issue, as the host cc also seems to leak sometimes (impurity)
      cmake = let
        wrapped-cmake = pkgs.writeShellScript "wrapped-cmake" ''
          ${super.cmake}/bin/cmake "$@" -DCMAKE_C_COMPILER=${zig-stdenv.cc}/bin/cc -DCMAKE_CXX_COMPILER=${zig-stdenv.cc}/bin/c++
        '';
      in pkgs.symlinkJoin {
        name = "cmake-wrapped";
        paths = [ super.cmake ];
        postBuild = ''
          rm $out/bin/cmake
          ln -s ${wrapped-cmake} $out/bin/cmake
        '';
      };
    })];

    crossOverlays = [(self: super: {
      stdenv = zig-stdenv;

      # XXX: libsepol issue on darwin, should be fixed upstrem instead
      libsepol = super.libsepol.overrideAttrs (old: {
        nativeBuildInputs = with pkgs; old.nativeBuildInputs ++ optionals (stdenv.isDarwin) [
          (writeShellScriptBin "gln" ''${pkgs.coreutils}/bin/ln "$@"'')
        ];
      });
    })];
  });
in {
  inherit target wrapRustToolchain;
  stdenv = zig-stdenv;
  pkgs = cross;
}
