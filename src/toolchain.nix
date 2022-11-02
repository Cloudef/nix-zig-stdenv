{
  utils,
  lib,
  writeShellScript,
  mkDerivation,
  emptyFile,
  wrapCCWith,
  wrapBintoolsWith,
  gnugrep,
  coreutils,
  libc,
  llvm,
  zig,
  localSystem,
  targetSystem,
  targetPkgs,
}:

with lib;
with builtins;

let
  zig-target = utils.nixTargetToZigTarget targetSystem.parsed;
  write-wrapper = cmd: writeShellScript "zig-${cmd}" ''${zig}/bin/zig ${cmd} "$@"'';
  toolchain-unwrapped = let
    prefix =
    if localSystem.config != targetSystem.config
    then "${targetSystem.config}-"
    else "";
  in mkDerivation {
    name = "zig-toolchain";
    inherit (zig) version;

    isClang = true;
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      mkdir -p $out/bin $out/lib
      for prog in ${llvm}/bin/*; do
        ln -sf $prog $out/bin/${prefix}$(basename $prog)
      done

      ln -s ${llvm}/bin/llvm-as $out/bin/${prefix}as
      ln -s ${llvm}/bin/llvm-dwp $out/bin/${prefix}dwp
      ln -s ${llvm}/bin/llvm-nm $out/bin/${prefix}nm
      ln -s ${llvm}/bin/llvm-objcopy $out/bin/${prefix}objcopy
      ln -s ${llvm}/bin/llvm-objdump $out/bin/${prefix}objdump
      ln -s ${llvm}/bin/llvm-readelf $out/bin/${prefix}readelf
      ln -s ${llvm}/bin/llvm-size $out/bin/${prefix}size
      ln -s ${llvm}/bin/llvm-strip $out/bin/${prefix}strip
      ln -s ${llvm}/bin/llvm-rc $out/bin/${prefix}windres

      for f in ld ar ranlib dlltool lib; do
        rm -f ${prefix}$f
      done

      ln -s ${write-cc-wrapper "cc"} $out/bin/clang
      ln -s ${write-cc-wrapper "c++"} $out/bin/clang++
      ln -s ${write-wrapper "ld"} $out/bin/${prefix}ld
      ln -s ${write-wrapper "ar"} $out/bin/${prefix}ar
      ln -s ${write-wrapper "ranlib"} $out/bin/${prefix}ranlib
      ln -s ${write-wrapper "dlltool"} $out/bin/${prefix}dlltool
      ln -s ${write-wrapper "lib"} $out/bin/${prefix}lib
    '';

  # Compatibility packages here:
  propagatedBuildInputs = with targetPkgs; if targetPkgs == {} then [] else []
  ++ optionals (targetSystem.parsed.kernel.name == "darwin") [
    # TODO: zig seems to be missing <err.h>
    darwin.apple_sdk.frameworks.CoreFoundation
  ];
  };
in wrapCCWith {
  inherit gnugrep coreutils libc;
  cc = toolchain-unwrapped;
  libcxx = toolchain-unwrapped;

  bintools = wrapBintoolsWith {
    inherit gnugrep coreutils libc;
    bintools = toolchain-unwrapped;
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
}
