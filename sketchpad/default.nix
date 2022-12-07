{
  pkgs ? import <nixpkgs> {},
  stdenv ? pkgs.stdenvNoCC,
  lib ? pkgs.lib,
  utils ? import ../src/utils.nix { inherit lib; },
  target ? builtins.currentSystem,
  static ? utils.supportsStatic target,
  without-libc ? false,
  zig-version ? "0.10.0",
  ...
} @args:

with lib;
with builtins;

let
  # for rust
  naersk-for-zig = zig: let
    cross = import ./.. { inherit pkgs zig target static; };
    fenix = import (fetchTarball "https://github.com/nix-community/fenix/archive/5fe1e430e990d5b0715f82dbd8b6c0cb7086c7e1.tar.gz") {};
    rust-toolchain = with fenix; combine [ minimal.rustc minimal.cargo targets.${cross.target}.latest.rust-std ];
    naersk = import (pkgs.fetchFromGitHub {
      owner = "nix-community";
      repo = "naersk";
      rev = "6944160c19cb591eb85bbf9b2f2768a935623ed3";
      hash = "sha256-9o2OGQqu4xyLZP9K6kNe1pTHnyPz0Wr3raGYnr9AIgY=";
    }) {
      inherit (cross) stdenv;
      inherit (pkgs) darwin fetchurl jq lib remarshal rsync runCommandLocal writeText zstd;
      inherit (pkgs.xorg) lndir;
      cargo = cross.wrapRustToolchain rust-toolchain;
      rustc = cross.wrapRustToolchain rust-toolchain;
    };
  in naersk;

  # defaults
  zig = (import ../versions.nix {})."${zig-version}";
  cross = import ./.. { inherit pkgs zig target static without-libc; };
  buildRustPackage = (naersk-for-zig zig).buildPackage;
in {
  # minimal glib, the default in nixpkgs is quite large and needs a lot of stuff
  glib = import ./glib { inherit pkgs cross; };

  # NOTE: this only supports aarch64 target for now (only musl is tested!)
  # NOTE: cross-compiling `rusty-v8` needs `qemu-binfmt` setup so that you can execute the build time binaries
  # XXX: investigate if the crackjob GN build environment can be made to cross-compile without qemu-binfmt
  #      or if we can compile the build time tools it needs beforehand without it knowing
  rusty-v8 = import ./rusty-v8 { inherit pkgs cross buildRustPackage glib; };

  # if you want to compile with `rusty-v8` derivation above, use `--arg with-rusty-v8 true`
  # otherwise you need to add the `librusty_v8-aarch64-unknown-linux-musl.a` to your nix store,
  # by running: `nix store add-file librusty_v8-aarch64-unknown-linux-musl.a`
  # NOTE: on linux you may have to build with `--argstr zig-version 0.8.1`
  deno-core-hello-world = let
    prebuilt = storePath /nix/store/v6a39mcfnijv11d05m77y4qpbkxr8ay3-librusty_v8-aarch64-unknown-linux-musl.a;
    artifact = "${rusty-v8}/lib/librusty_v8.a";
  in import ./rusty-v8/hello.nix {
    inherit pkgs buildRustPackage;
    librusty-v8 = if args ? with-rusty-v8 && args.with-rusty-v8 then artifact else prebuilt;
  };
}
