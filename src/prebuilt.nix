{ pkgs, crossSystem, stdenv ? pkgs.stdenvNoCC }:

with builtins;
with pkgs.lib;

let
  target = crossSystem.config;
  cache-dynamic = import ./prebuilt-derive-from.nix { inherit target; };
  cache-static = import ./prebuilt-derive-from.nix { target = "${target}-static"; };
  nixpkgs = splitString "\n" (readFile ../meta/nixpkgs);
  prebuilt-or-error = with pkgs; pkg: let
    is-prebuilt = target: readFile (runCommandLocal "${target}-${pkg}-is-prebuilt" {} ''
      ${pkgs.nix}/bin/nix-env -qaPb --no-name -f ${./prebuilt-derive-from.nix} --argstr target "${target}" --argstr utilsp ${./utils.nix} -A "${pkg}" > $out
    '') == pkg;
  in {}
  // optionalAttrs (is-prebuilt target) { dynamic = cache-dynamic.pkgs."${p}"; }
  // optionalAttrs (is-prebuilt "${target}-static") { static = cache-static.pkgs."${p}"; };
in genAttrs nixpkgs (pkg: prebuilt-or-error pkg)
