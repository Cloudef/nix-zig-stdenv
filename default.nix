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
} @args:

with lib;

let
  to-system = x: systems.elaborate ({ config = x; isStatic = static; }
  // optionalAttrs (hasSuffix "mingw32" x) { libc = "msvcrt"; }
  // optionalAttrs (hasSuffix "darwin" x) { libc = "libSystem"; }
  // optionalAttrs (hasSuffix "wasi" x) { libc = "wasilibc"; }
  // optionalAttrs (hasInfix "musl" x) { libc = "musl"; }
  // optionalAttrs (hasInfix "gnu" x) { libc = "glibc"; }
  );

  localSystem = pkgs.buildPlatform;
  crossSystem = if isAttrs args.target then target else to-system target;
  config = (args.config or {}) // { allowUnsupportedSystem = localSystem.config != crossSystem.config; };

  utils = import ./src/utils.nix { inherit lib; };

  wrapper = import ./src/wrapper.nix {
    inherit lib;
    inherit (pkgs) writeShellScript symlinkJoin;
  };

  rust-wrapper = import ./src/rust-support.nix {
    inherit lib wrapper static;
    inherit (pkgs) writeShellScript;
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
    cross0 = import pkgs.path {
      inherit localSystem crossSystem config;
      stdenvStages = import ./src/stdenv.nix {
        inherit (pkgs) path;
        inherit mk-zig-toolchain native-toolchain;
      };
    };
    lib = with cross0.pkgs; {
      msvcrt = null;
      libSystem = null;
      wasilibc = null;
      musl = musl.overrideAttrs(o: {
        outputs = [ "out" ];
        CFLAGS = []; # -fstrong-stack-protection is not allowed
        separateDebugInfo = false;
        postInstall = "ln -rs $out/lib/libc.so $out/lib/libc.musl-${crossSystem.parsed.cpu.name}.so.1";
      });
      # XXX: glibc does not compile with anything else than GNU tools while you can compile to
      #      glibc platforms, you won't be able to execute cross-compiled binaries inside a
      #      qemu-static-user environment for example
      glibc = if localSystem == crossSystem then glibc else null; # callPackage "${pkgs.path}/pkgs/development/libraries/glibc" {};
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
}
