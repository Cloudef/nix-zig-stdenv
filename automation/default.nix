with builtins;

let
  pkgs = import <nixpkgs> {
    overlays = [(import ../overlay.nix { allowBroken = true; })];
  };
in {
  inherit (pkgs) zigVersions zigCross;
}
