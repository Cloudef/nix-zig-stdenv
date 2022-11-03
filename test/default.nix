{ allow-broken ? true }:

with builtins;

let
  overlay =
  (self: super: {
    super-simple = let
      src = self.writeText "hello.c" ''
        #include <stdio.h>
        int main() {
           printf("hello world\n");
           return 0;
        }
      '';
    in self.stdenv.mkDerivation {
      name = "hello";
      dontUnpack = true;
      dontConfigure = true;
      buildPhase = "$CC ${src} -o hello";
      installPhase = "install -Dm755 hello -t $out";
    };
  });

  layer = import <nixpkgs> {
    overlays = [ overlay (import ../overlay.nix { allowBroken = allow-broken; }) ];
  };
in with layer; with layer.lib; {
  inherit zigVersions;
  list-versions = attrNames zigVersions;
  list-targets = { version }: attrNames zigVersions.${version}.targets;
  install-version = { version }: zigVersions."${version}".zig;
  build-package = { version, target, package }: zigVersions."${version}".targets."${target}".pkgs."${package}";
}
