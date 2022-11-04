with builtins;

let
  pkgs = import <nixpkgs> {
    overlays = [(import ../overlay.nix { allowBroken = true; })];
  };

  versions = attrNames pkgs.zigVersions;
  targets = attrNames pkgs.zigVersions.master.targets;
in {
  inherit versions targets;
}
