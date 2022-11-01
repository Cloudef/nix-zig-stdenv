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
    inherit (pkgs) writeShellScript symlinkJoin;
  };

  rust-wrapper = import ./src/rust-support.nix {
    inherit lib wrapper static;
    inherit (pkgs) writeShellScript;
  };

  # FIXME: get rid of this, used only to refer to local zig cc
  local0 = import pkgs.path {
    inherit localSystem config;
    crossSystem = localSystem;
    stdenvStages = import ./src/stdenv.nix {
      inherit (pkgs) path;
      inherit (pkgs.llvmPackages) llvm;
      inherit utils zig;
    };
  };

  # Used to compile and install compatibility packages
  cross0 = import pkgs.path {
    inherit localSystem crossSystem config;
    stdenvStages = import ./src/stdenv.nix {
      inherit (pkgs) path;
      inherit (pkgs.llvmPackages) llvm;
      inherit utils zig;
    };
  };

  cross-env = import pkgs.path {
    inherit localSystem crossSystem config;

    stdenvStages = import ./src/stdenv.nix {
      inherit (pkgs) path;
      inherit (pkgs.llvmPackages) llvm;
      inherit utils zig cross0;
    };

    # TODO: check if any of these are needed anymore
    overlays = [(self: super: {
      rust = rust-wrapper super.rust local0.stdenv.cc localSystem.config super.stdenv.cc crossSystem.config;
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
  inherit (cross-env) stdenv;
  target = crossSystem.config;
  pkgs = cross-env;
  wrapRustToolchain = toolchain: rust-wrapper toolchain local0.stdenv.cc localSystem.config cross-env.stdenv.cc crossSystem.config;
}
