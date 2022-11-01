{ pkgs ? import <nixpkgs> {}, lib ? pkgs.lib, stdenv ? pkgs.stdenvNoCC, system ? builtins.currentSystem }:

with lib;
with builtins;

let
  zig-system = concatStringsSep "-" (map (x: if x == "darwin" then "macos" else x) (splitString "-" system));
in filterAttrs (n: v: v != null) (mapAttrs (k: v: let
  res = v."${zig-system}" or null;
in if res == null then null else stdenv.mkDerivation {
  pname = "zig";
  version = if k == "master" then v.version else k;
  isMasterBuild = k == "master";

  src = pkgs.fetchurl {
    url = res.tarball;
    sha256 = res.shasum;
  };

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    mkdir -p $out/{doc,bin,lib}
    [[ -d docs ]] && cp -r docs/* $out/doc
    [[ -d doc ]] && cp -r doc/* $out/doc
    cp -r lib/* $out/lib
    install -Dm755 zig $out/bin/zig
  '';

  meta = with lib; {
    homepage = "https://ziglang.org/";
    description = "General-purpose programming language and toolchain for maintaining robust, optimal, and reusable software";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}) (fromJSON (readFile ./versions.json)))
