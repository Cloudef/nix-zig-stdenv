{ pkgs, cross, buildRustPackage, glib, lib ? pkgs.lib, stdenv ? pkgs.stdenvNoCC }:

with lib;

assert cross.stdenv.targetPlatform.isAarch64;

let
  gn-ninja = rec {
    version = "20220517";

    src = fetchTarball {
      url = "https://github.com/denoland/ninja_gn_binaries/archive/${version}.tar.gz";
    };

    gn = stdenv.mkDerivation {
      inherit version src;
      name = "gn";

      dontPatch = true;
      dontConfigure = true;
      dontBuild = true;

      nativeBuildInputs = with pkgs; [ autoPatchelfHook ];

      installPhase = if stdenv.isLinux
      then "install -Dm 755 linux64/gn $out/bin/gn"
      else "install -Dm 755 mac/gn $out/bin/gn";

      meta = with lib; {
        description = "A meta-build system that generates build files for Ninja";
        homepage = "https://gn.googlesource.com/gn";
        license = licenses.bsd3;
        platforms = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
      };
    };

    ninja = stdenv.mkDerivation {
      inherit version src;
      name = "ninja";

      dontPatch = true;
      dontConfigure = true;
      dontBuild = true;

      nativeBuildInputs = with pkgs.buildPackages; [ autoPatchelfHook ] ++
      optionals (stdenv.isLinux) [ gcc.cc.lib ]; # libstdc++.so.6

      installPhase = if stdenv.isLinux
      then "install -Dm 755 linux64/ninja $out/bin/ninja"
      else "install -Dm 755 mac/ninja $out/bin/ninja";

      meta = with lib; {
        description = "Small build system with a focus on speed";
        homepage = "https://ninja-build.org/";
        license = licenses.asl20;
        platforms = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
      };
    };
  };

  rusty = {
    name = "rusty_v8";
    version = "0.53.1";
    clang = pkgs.runCommandLocal "clang" {} ''
      mkdir -p $out/bin
      ln -s ${cross.stdenv.cc}/bin/${cross.target}-cc $out/bin/clang
      ln -s ${cross.stdenv.cc}/bin/${cross.target}-c++ $out/bin/clang++
      ln -s ${cross.stdenv.cc}/bin/${cross.target}-ar $out/bin/llvm-ar
    '';
  };
in buildRustPackage {
  inherit (rusty) name version;

  src = pkgs.fetchFromGitHub {
    owner = "denoland";
    repo =  rusty.name;
    rev = "v${rusty.version}";
    sha256 = "sha256-QKriAHAS6Egq7KdwKQmmhSm1u765W5qPngd2X4DHcQM=";
    fetchSubmodules = true;
  };

  copyTarget = false;
  copyBins = false;

  nativeBuildInputs = with pkgs.buildPackages; [ python3 gn-ninja.gn gn-ninja.ninja pkg-config ];
  buildInputs = [ glib ];

  V8_FROM_SOURCE = true;

  # TODO: this needs to be mapped
  GN_ARGS = ''target_os="linux" target_cpu="arm64" use_custom_libcxx=false is_clang=true v8_snapshot_toolchain="//build/toolchain/linux/unbundle:default"'';

  # XXX: zig cc doesn't handle some CLI arguments
  CLANG_BASE_PATH = rusty.clang;
  NIX_DEBUG = 1;

  postInstall = ''
    mkdir -p $out/lib
    cp target/${cross.target}/release/gn_out/obj/librusty_v8.a $out/lib/librusty_v8.a
  '';
}
