{
  pkgs ? import <nixpkgs> {},
  lib ? pkgs.lib,
  config ? {},
  overlays ? [],
  crossOverlays ? [],
  zig ? pkgs.zig,
  utils ? import ./src/utils.nix { inherit lib; },
  target ? builtins.currentSystem,
  static ? utils.supportsStatic target,
  ...
} @args:

with lib;

let
  localSystem = pkgs.buildPlatform;
  crossSystem = if isAttrs target then utils.elaborate target else utils.targetToNixSystem target static;
  config = (args.config or {}) // { allowUnsupportedSystem = localSystem.config != crossSystem.config; };

  wrapper = import ./src/wrapper.nix {
    inherit lib;
    inherit (pkgs) writeShellScript symlinkJoin;
  };

  rust-wrapper = import ./src/rust-support.nix {
    inherit lib wrapper static;
    inherit (pkgs) writeShellScript;
  };

  prebuilt = import ./src/prebuilt.nix {
    inherit pkgs crossSystem;
  };

  mk-zig-toolchain = import ./src/toolchain.nix {
    inherit (pkgs) writeShellScript emptyFile gnugrep coreutils;
    inherit (pkgs.llvmPackages) llvm;
    inherit localSystem utils lib zig;
  };

  # First native zig toolchain
  native-toolchain = mk-zig-toolchain {
    inherit (pkgs) wrapCCWith wrapBintoolsWith;
    inherit (pkgs.stdenvNoCC) mkDerivation;
    inherit (pkgs.stdenv.cc) libc;
    targetSystem = localSystem;
    targetPkgs = pkgs;
  };

  libc = let
    # For compiling libc from scratch
    # Not used if there's prebuilt libc available
    cross0 = (import pkgs.path {
      inherit localSystem crossSystem config;
      stdenvStages = import ./src/stdenv.nix {
        inherit (pkgs) path;
        inherit mk-zig-toolchain native-toolchain;
      };
    }).pkgs;
    lib = {
      msvcrt = null;
      libSystem = null;
      wasilibc = null;
      musl = prebuilt.musl.dynamic or cross0.musl.overrideAttrs(o: {
        outputs = [ "out" ];
        CFLAGS = []; # -fstrong-stack-protection is not allowed
        separateDebugInfo = false;
        postInstall = "ln -rs $out/lib/libc.so $out/lib/libc.musl-${crossSystem.parsed.cpu.name}.so.1";
      });
      # XXX: glibc does not compile with anything else than GNU tools while you can compile to
      #      glibc platforms, you won't be able to execute cross-compiled binaries inside a
      #      qemu-static-user environment for example
      glibc = prebuilt.glibc.dynamic or null;
    };
  in lib."${crossSystem.libc}" or (throw "Could not understand the required libc for target: ${target}");

  # Used to compile and install compatibility packages
  targetPkgs = import pkgs.path {
    inherit localSystem crossSystem config;
    stdenvStages = import ./src/stdenv.nix {
      inherit (pkgs) path;
      inherit mk-zig-toolchain native-toolchain libc;
    };
  };

  cross-env = import pkgs.path {
    inherit localSystem crossSystem config;
    stdenvStages = import ./src/stdenv.nix {
      inherit (pkgs) path;
      inherit mk-zig-toolchain native-toolchain targetPkgs libc;
    };

    overlays = [(self: super: {
      rust = rust-wrapper super.rust native-toolchain localSystem.config super.stdenv.cc crossSystem.config;
    })] ++ overlays;

    # TODO: check the fixes here
    # TODO: test for every issue
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
  wrapRustToolchain = toolchain: rust-wrapper toolchain native-toolchain localSystem.config cross-env.stdenv.cc crossSystem.config;
  experimental = { inherit prebuilt; };
}
