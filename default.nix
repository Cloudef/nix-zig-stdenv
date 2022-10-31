{
  pkgs ? import <nixpkgs> {},
  lib ? pkgs.lib,
  config ? {},
  overlays ? [],
  crossOverlays ? [],
  zig ? pkgs.zig,
  static ? true,
  target ? builtins.currentSystem,
  ...
}:

# TODO: static == true && glibc target should result in evaluation error

with lib;

let
  to-system = x: systems.elaborate (
    if hasSuffix "mingw32" x then { config = x; libc = "msvcrt"; isStatic = static; }
    else { config = x; isStatic = static; }
    );

  localSystem = pkgs.buildPlatform;
  crossSystem = if isAttrs target then target else to-system target;

  utils = import ./src/utils.nix { inherit lib; };

  wrapper = import ./src/wrapper.nix {
    inherit lib;
    inherit (pkgs) writeShellScript;
  };

  wrapRustToolchain = import ./src/rust-support.nix {
    inherit lib wrapper static;
    inherit (pkgs) writeShellScript;
  };

  cross-env = import pkgs.path {
    inherit localSystem crossSystem config;

    stdenvStages = import ./src/stdenv.nix {
      inherit (pkgs) path;
      inherit (pkgs.llvmPackages) llvm;
      inherit utils zig;
    };

    # TODO: check if any of these are needed anymore
    overlays = [(self: super: {
      # rust = wrapRustToolchain super.rust pkgs.stdenv.cc local-system.config cross-system.config;

      # cmake sucks at picking up the right compiler ...
      # probably darwin only issue, as the host cc also seems to leak sometimes (impurity)
      # cmake = wrapper super.cmake [{
      #   wrapper = ''${super.cmake}/bin/cmake "$@" -DCMAKE_C_COMPILER=${zig-stdenv.cc}/bin/cc -DCMAKE_CXX_COMPILER=${zig-stdenv.cc}/bin/c++'';
      #   path = "bin/cmake";
      # }];
    })] ++ overlays;

    crossOverlays = [(self: super: {
      # XXX: broken on aarch64 at least
      gmp = super.gmp.overrideAttrs (old: {
        configureFlags = old.configureFlags ++ [ "--disable-assembly" ];
      });

      # XXX: libsepol issue on darwin, should be fixed upstream instead
      libsepol = super.libsepol.overrideAttrs (old: {
        nativeBuildInputs = with pkgs; old.nativeBuildInputs ++ optionals (stdenv.isDarwin) [
          (writeShellScriptBin "gln" ''${coreutils}/bin/ln "$@"'')
        ];
      });
    })] ++ crossOverlays;
  };
in {
  inherit target;
  inherit (cross-env) stdenv;
  pkgs = cross-env;
}
