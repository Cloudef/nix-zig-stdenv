{ target }:

let
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/refs/tags/22.05.tar.gz";
    sha256 = "0d643wp3l77hv2pmg2fi7vyxn4rwy0iyr8djcw1h5x72315ck9ik";
  };
  pkgs = import nixpkgs {};
  utils = import ./utils.nix { inherit (pkgs) lib; };
  isStatic = with pkgs.lib; hasSuffix "-static" target;
  localSystem = with pkgs.lib; utils.targetToNixSystem (removeSuffix "-static" target) isStatic;
in with pkgs.lib; import nixpkgs {
  inherit localSystem;
  overlays = [] ++ optionals (isStatic) [
    (self: super: {
      # error: attribute 'pam' missing
      libcap_pam = null;
    })
  ] ;
}
