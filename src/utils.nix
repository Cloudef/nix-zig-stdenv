{ lib }:

with lib;

{
  zigTargetToNixTarget = target: let
    kernel = {
      freestanding = l: "${head l}-unknown-none-${last l}";
      linux = l: "${head l}-unknown-linux-${last l}";
      macos = l: "${head l}-apple-darwin";
      windows = l: "${head l}-w64-mingw32";
      wasi = l: "${head l}-unknown-wasi";
    };
    cpu = {
      powerpc64 = s: "${s}abi64";
      sparcv9 = s: "sparc64-${removePrefix "sparcv9-" s}";
      thumb = s: "armv5tel-${removePrefix "thumb-" s}";
    };
    split = splitString "-" target;
  in cpu."${head split}" or (_: _) (kernel."${elemAt split 1}" split);

  nixTargetToZigTarget = target: let
    kernel = {
      none = t: "${t.cpu.name}-freestanding-${t.abi.name}";
      linux = t: "${t.cpu.name}-linux-${t.abi.name}";
      darwin = t: "${t.cpu.name}-macos-none";
      windows = t: "${t.cpu.name}-windows-gnu";
      wasi = t: "${t.cpu.name}-wasi-musl";
    };
    cpu = {
      powerpc64 = s: removeSuffix "abi64" s;
      sparc64 = s: "sparcv9-${removePrefix "sparc64-" s}";
      armv5tel = s: "thumb-${removePrefix "armv5tel-" s}";
    };
  in cpu."${target.cpu.name}" or (_: _) (kernel."${target.kernel.name}" target);
}
