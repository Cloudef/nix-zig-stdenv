{ lib, writeShellScript }:

with lib;

drv: wrappers: let
  mapped = map (x: { wrapper = writeShellScript "wrapper" x.script; path = x.path; }) wrappers;
in symlinkJoin {
  name = "${drv.name}-wrapped";
  paths = [ drv ];
  postBuild = concatStringsSep "\n" (flatten (map (x: [ "rm $out/${x.path}" "ln -s ${x.wrapper} $out/${x.path}" ]) mapped));
}
