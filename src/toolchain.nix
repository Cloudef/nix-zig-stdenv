{
  utils,
  lib,
  writeShellScript,
  linkFarm,
  emptyFile,
  wrapCCWith,
  wrapBintoolsWith,
  gnugrep,
  coreutils,
  llvm,
  zig,
  targetSystem
}:

with lib;
with builtins;

let
  zig-target = utils.nixTargetToZigTarget targetSystem.parsed;

  wrap-toolchain = toolchain: wrapCCWith rec {
    inherit gnugrep coreutils;
    cc = toolchain;
    libc = toolchain;
    libcxx = toolchain;

    bintools = wrapBintoolsWith {
      inherit libc gnugrep coreutils;
      bintools = toolchain;
      postLinkSignHook = emptyFile;
      signingUtils = emptyFile;
    };

    # XXX: -march and -mcpu are not compatible
    #      https://github.com/ziglang/zig/issues/4911
    extraBuildCommands = ''
      substituteInPlace $out/nix-support/add-local-cc-cflags-before.sh --replace "${targetSystem.config}" "${zig-target}"
      sed -i 's/\([^ ]\)-\([^ ]\)/\1_\2/g' $out/nix-support/cc-cflags-before || true
      sed -i 's/-arch [^ ]* *//g' $out/nix-support/cc-cflags || true
    '' + (optionalString (
      targetSystem.parsed.cpu.name == "aarch64" || targetSystem.parsed.cpu.name == "aarch64_be" ||
      targetSystem.parsed.cpu.name == "armv5tel" || targetSystem.parsed.cpu.name == "mipsel") ''
      # error: Unknown CPU: ...
      sed -i 's/-march[^ ]* *//g' $out/nix-support/cc-cflags-before || true
    '') + (optionalString (targetSystem.parsed.cpu.name == "s390x") ''
      printf " -march=''${S390X_MARCH:-arch8}" >> $out/nix-support/cc-cflags-before
    '');
  };

  write-wrapper = cmd: writeShellScript "zig-${cmd}" ''${zig}/bin/zig ${cmd} "$@"'';

  symlinks = [
    { name = "bin/clang"; path = write-wrapper "cc"; }
    { name = "bin/clang++"; path = write-wrapper "c++"; }
    { name = "bin/ld"; path = write-wrapper "cc"; }
    { name = "bin/ar"; path = write-wrapper "ar"; }
    { name = "bin/ranlib"; path = write-wrapper "ranlib"; }
    { name = "bin/dlltool"; path = write-wrapper "dlltool"; }
    { name = "bin/lib"; path = write-wrapper "lib"; }
    { name = "bin/windres"; path = "rc"; }
  ] ++ map (x: { name = "bin/${x}"; path = "${llvm}/bin/llvm-${x}"; }) [
    "addr2line" "as" "dwarfdump" "lipo" "install-name-tool" "nm" "objcopy" "objdump" "rc" "readelf" "size" "strings" "strip"
  ] ++ map (x: { name = "bin/llvm-${x}"; path = "${llvm}/bin/llvm-${x}"; }) [
    "cat" "cov" "c-test" "cfi-verify" "bcanalyzer" "cvtres" "cxxdump" "cxxfilt" "cxxmap" "diff" "dis" "dwp" "elfabi" "rtdyld"
    "exegesis" "extract" "gsymutil" "ifs" "link" "lto" "lto2" "jitlink" "split" "stress" "symbolizer" "tblgen" "undname" "xray"
    "opt-report" "pdbutil" "profdata" "mc" "mca" "ml" "modextract" "mt" "readobj" "reduce"
  ];
in wrap-toolchain ((linkFarm "zig-toolchain" symlinks) // {
  inherit (zig) version;
  isClang = true;
})
