with builtins;

let
  versions = import ../versions.nix {};
  pkgs = import <nixpkgs> {
    overlays = [(import ../overlay.nix {
      zig = versions.master;
      allowBroken = true;
    })];
  };
in {
  inherit (pkgs) zigVersions zigCross;
}
