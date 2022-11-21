{ pkgs, librusty-v8, buildRustPackage, lib ? pkgs.lib, stdenv ? pkgs.stdenvNoCC }:

with lib;
with builtins;

let
  nix-filter = import (pkgs.fetchFromGitHub {
    owner = "numtide";
    repo = "nix-filter";
    rev = "3b821578685d661a10b563cba30b1861eec05748";
    hash = "sha256-RizGJH/buaw9A2+fiBf9WnXYw4LZABB5kMAZIEE5/T8=";
  });
in buildRustPackage rec {
  name = "deno-core-hello-world";
  pname = name;
  stripAllList = [ "bin" ];

  src = nix-filter {
    root = ./deno-core-hello-world;
    include = [
      ./deno-core-hello-world/src
      ./deno-core-hello-world/Cargo.toml
      ./deno-core-hello-world/Cargo.lock
    ];
  };

  RUSTY_V8_ARCHIVE = librusty-v8;
  NIX_CFLAGS_COMPILE = [ "-lc++" librusty-v8 ];
}
