{ pkgs, crossSystem, stdenv ? pkgs.stdenvNoCC }:

with builtins;
with pkgs.lib;

let
  target = crossSystem.config;
  cache-dynamic = import ./prebuilt-derive-from.nix { inherit pkgs target; };
  cache-static = import ./prebuilt-derive-from.nix { inherit pkgs; target = "${target}-static"; };
  prebuilt = fromJSON (readFile ../meta/prebuilt.json);
in {
  static = genAttrs (prebuilt."${target}-static" or []) (pkg: cache-static.pkgs."${pkg}");
  dynamic = genAttrs (prebuilt."${target}" or []) (pkg: cache-dynamic.pkgs."${pkg}");
}
