{
  description = "nix-zig stdenv";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-23.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }: let
    systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    outputs = flake-utils.lib.eachSystem systems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      versions = import ./versions.nix { inherit system pkgs; };
      apps = rec {
        default = apps.zig;
        zig = flake-utils.lib.mkApp { drv = versions.master; };
      };
    });
  in
    outputs // {
      overlays.default = final: prev: {
        versions = outputs.versions;
      };
    };
}
