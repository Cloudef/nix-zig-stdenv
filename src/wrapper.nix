{ lib, writeShellScript, symlinkJoin }:

with lib;

drvs: wrappers: let
  mapped = map (x: { wrapper = writeShellScript "wrapper" x.script; path = x.path; }) wrappers;
in symlinkJoin {
  name = "${(head drvs).name}-wrapped";
  paths = drvs;
  postBuild = concatStringsSep "\n" (flatten (map (x: [ "rm -f $out/${x.path}" "ln -s ${x.wrapper} $out/${x.path}" ]) mapped));
}
