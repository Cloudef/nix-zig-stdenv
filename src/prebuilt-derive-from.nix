{ pkgs ? import <nixpkgs> {}, target }:

let
  utils = import ./utils.nix { inherit (pkgs) lib; };
  isStatic = with pkgs.lib; hasSuffix "-static" target;
  localSystem = with pkgs.lib; utils.targetToNixSystem (removeSuffix "-static" target) isStatic;
in with pkgs.lib; import pkgs.path {
  inherit localSystem;
  overlays = [] ++ optionals (isStatic) [
    (self: super: {
      # error: attribute 'pam' missing
      libcap_pam = null;
    })
  ] ;
}
