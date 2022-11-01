{ zig ? null, static ? true, allowBroken ? false } @args:

with builtins;

pkgs: super: with pkgs.lib; let
  utils = import ./src/utils.nix { inherit (pkgs) lib; };
  versions = import ./versions.nix { inherit pkgs; };
  zig = if args.zig != null then args.zig else super.zig;

  gen-targets = zig: let
    zig-targets = with pkgs; (fromJSON (readFile (runCommand "targets" {} ''${zig}/bin/zig targets > $out''))).libc;

    # TODO: automate these for each zig version with github actions
    broken = if args.allowBroken then [] else ([
      # error: container 'std.os.linux' has no member called 'syscall3'
      # https://github.com/ziglang/zig/issues/8020
      "mips64-unknown-linux-musl"
      "mips64el-unknown-linux-musl"
      # error: unknown type name '__time64_t'
      "mips64el-unknown-linux-gnuabi64"
      "mips64-unknown-linux-gnuabi64"
      # Assertion failed at /tmp/nix-build-zig-0.9.1.drv-0/source/src/stage1/codegen.cpp:9576 in init. This is a bug in the Zig compiler.thread 32789044
      # panic: Unable to dump stack trace: debug info stripped
      "mips64el-unknown-linux-gnuabin32"
      "mips64-unknown-linux-gnuabin32"
      # error: unknown emulation: elf32_sparc
      "sparc-unknown-linux-gnu"
      # error: unexpected token sethi %gdop_hix22(__gmon_start__), %g1
      "sparc64-unknown-linux-gnu"
      # fatal error: 'arm-features.h' file not found
      # https://github.com/ziglang/zig/issues/3287
      "arm-unknown-linux-gnueabihf"
      "arm-unknown-linux-gnueabi"
      # completely broken, headers blow up
      "armv5tel-unknown-linux-gnueabi"
      "armv5tel-unknown-linux-gnueabihf"
      # fatal error: error in backend: unsupported relocation type: fixup_arm_uncondbl
      "arm-w64-mingw32"
      # error: Only Win32 target is supported!
      "aarch64_be-w64-mingw32"
      # error: unknown emulation: aarch64_be_linux
      "aarch64_be-unknown-linux-gnu"
      "aarch64_be-unknown-linux-musl"
      # error: unknown emulation: elf64_s390
      "s390x-unknown-linux-gnu"
      "s390x-unknown-linux-musl"
      # error: unknown directive .cfi_label .Ldummy
      "riscv64-unknown-linux-gnu"
      # line 2: 40398 Trace/BPT trap: 5
      "m68k-unknown-linux-musl"
      # error: unable to create target: 'No available targets are compatible with triple "m68k-unknown-linux-gnu"
      "m68k-unknown-linux-gnu"

      # hangs with high cpu usage (inifinite loop?)
      "powerpc64le-unknown-linux-gnu"
      "powerpc64le-unknown-linux-musl"

      # works, but not useful as a zigCross target
      # you can import it manually if you want
      "wasm32-unknown-none-musl"

      # Not supported by nixpkgs/systems/parse.nix
      "csky-unknown-linux-gnueabi"
      "csky-unknown-linux-gnueabihf"
      "x86_64-unknown-linux-gnux32"
      "armeb-unknown-linux-gnueabi"
      "armeb-unknown-linux-musleabi"
      "armeb-unknown-linux-gnueabihf"
      "armeb-unknown-linux-musleabihf"
      "armeb-w64-mingw32"
    ] ++ optionals (zig.isMasterBuild or false) [
      "armv5tel-unknown-linux-musleabihf"
      # ld.lld: error: relocation R_386_PC32 cannot be used against symbol '__gehf2'; recompile with -fPIC
      "i386-unknown-linux-gnu"
      "i386-unknown-linux-musl"
      # ld.lld: warning: lld uses blx instruction, no object with architecture supporting feature detected
      "armv5tel-unknown-linux-musleabi"
      # undefined symbol: _tls_index
      "i386-w64-mingw32"
    ]);
  in filter (x: !(any (y: x == y) broken)) (map utils.zigTargetToNixTarget zig-targets);

  gen-cross = zig: let
    targets = gen-targets zig;
    static-targets = targets ++ map (t: "${t}-static") targets;
    import-target-pkgs = target: (import ./default.nix {
      inherit pkgs target zig;
      inherit (pkgs) config overlays;
      static = hasSuffix "-static" target;
    }).pkgs;
  in genAttrs (targets ++ static-targets) import-target-pkgs;
in {
  zigCross = gen-cross zig;
  zigVersions = mapAttrs (k: v: {
    zig = v;
    pkgs = gen-cross v;
  }) (versions // { default = super.zig; });
}
