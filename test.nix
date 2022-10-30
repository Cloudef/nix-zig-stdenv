{ pkgs ? import <nixpkgs> {}, lib ? pkgs.lib, zigVersion ? null, allowBroken ? false }:

with lib;

let
  zigBinaries = import ./zig-binary.nix { inherit pkgs; };
  matrix = if zigVersion != null && zigVersion != (toString null) then [
    (import <nixpkgs> { overlays = [(import ./overlay.nix { inherit allowBroken; zig = zigBinaries."${zigVersion}"; })]; })
  ] else [
    (import <nixpkgs> { overlays = [(import ./overlay.nix { inherit allowBroken; })]; })
    (import <nixpkgs> { overlays = [(import ./overlay.nix { inherit allowBroken; zig = zigBinaries."0.9.1"; })]; })
    (import <nixpkgs> { overlays = [(import ./overlay.nix { inherit allowBroken; zig = zigBinaries."0.9.0"; })]; })
    (import <nixpkgs> { overlays = [(import ./overlay.nix { inherit allowBroken; zig = zigBinaries.master; })]; })
  ];
  build-pkgs = o: map (x: o.zigCross."${x}".iniparser.overrideAttrs (old: { doCheck = false; })) (attrNames o.zigCross);
in (map build-pkgs matrix) ++ optionals (zigVersion == null) (attrValues zigBinaries)
