{
  description = "nix-zig stdenv";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }: let
    systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    outputs = flake-utils.lib.eachSystem systems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      env = args: import ./default.nix (args // { inherit pkgs; });
      versions = import ./versions.nix { inherit system pkgs; };
      apps.zig = flake-utils.lib.mkApp { drv = versions.master; };
      apps.default = apps.zig;
    });
  in
    outputs // {
      overlays.default = final: prev: {
        versions = outputs.versions;
      };
    };
}
