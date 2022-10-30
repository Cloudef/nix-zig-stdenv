{ zig ? null, static ? true, allowBroken ? false }:

with builtins;

pkgs: super: with pkgs.lib; let
  _zig = if zig != null then zig else super.zig;
  targets = with pkgs; with lib; let
    zig-targets = (fromJSON (readFile (runCommand "targets" {} ''${_zig}/bin/zig targets > $out''))).libc;
    map-target = x: let
      splitted = splitString "-" x;
      kernel-map = {
        freestanding = y: "${head y}-unknown-none-${last y}";
        linux = y: "${head y}-unknown-linux-${last y}";
        macos = y: "${head y}-apple-darwin";
        windows = y: "${head y}-w64-mingw32";
        wasi = y: "${head y}-unknown-wasi";
      };
      cpu-map = {
        powerpc64 = y: "${y}abi64";
        sparcv9 = y: "sparc64-${removePrefix "sparcv9-" y}";
        thumb = y: "armv5tel-${removePrefix "thumb-" y}";
        armeb = y: "broken";
        csky = y: "broken";
      };
    in cpu-map."${head splitted}" or (_: _) (kernel-map."${elemAt splitted 1}" splitted);

    # TODO: automate these for each zig version with github actions
    broken = if allowBroken then [ "broken" ] else ([
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
      "x86_64-unknown-linux-gnux32"
      "broken"
    ] ++ optionals (_zig.isMasterBuild or false) [
      "armv5tel-unknown-linux-musleabihf"
      "aarch64-apple-darwin"
      "x86_64-apple-darwin"
      # ld.lld: error: relocation R_386_PC32 cannot be used against symbol '__gehf2'; recompile with -fPIC
      "i386-unknown-linux-gnu"
      "i386-unknown-linux-musl"
      # ld.lld: warning: lld uses blx instruction, no object with architecture supporting feature detected
      "armv5tel-unknown-linux-musleabi"
      # undefined symbol: _tls_index
      "i386-w64-mingw32"
    ]);
  in filter (x: !(any (y: x == y) broken)) (map map-target zig-targets);
in {
  zig = _zig;
  zigCross = pkgs.lib.genAttrs targets (target: (import ./default.nix { inherit pkgs target static; zig = _zig; }).pkgs);
  zigBinaries = import ./zig-binary.nix { inherit pkgs; };
}
