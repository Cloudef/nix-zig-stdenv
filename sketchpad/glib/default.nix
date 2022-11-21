{ pkgs, cross, lib ? pkgs.lib, stdenv ? cross.stdenv, fetchpatch ? pkgs.fetchpatch, fetchurl ? pkgs.fetchurl }:

with lib;

let
  # Some packages don't get "Cflags" from pkg-config correctly
  # and then fail to build when directly including like <glib/...>.
  # This is intended to be run in postInstall of any package
  # which has $out/include/ containing just some disjunct directories.
  flattenInclude = ''
    for dir in "''${!outputInclude}"/include/*; do
      cp -r "$dir"/* "''${!outputInclude}/include/"
      rm -r "$dir"
      ln -s . "$dir"
    done
    ln -sr -t "''${!outputInclude}/include/" "''${!outputInclude}"/lib/*/include/* 2>/dev/null || true
  '';

in stdenv.mkDerivation (finalAttrs: {
  pname = "glib";
  version = "2.74.0";

  src = fetchurl {
    url = "mirror://gnome/sources/glib/${lib.versions.majorMinor finalAttrs.version}/glib-${finalAttrs.version}.tar.xz";
    sha256 = "NlLH8HLXsDGmte3WI/d+vF3NKuaYWYq8yJ/znKda3TA=";
  };

  patches = optionals stdenv.isDarwin [
    (fetchpatch {
      name = "darwin-compilation.patch";
      url = "https://raw.githubusercontent.com/NixOS/nixpkgs/c987121acf5c87436a0b05ca75cd70bf38c452ca/pkgs/development/libraries/glib/darwin-compilation.patch";
      sha256 = "7d4c84277034fb8a1aad1d253344e91df89de2efa344a88627ad581c2cbd939b";
    })
  ] ++ optionals stdenv.hostPlatform.isMusl [
    (fetchpatch {
      name = "quark-init-on-demand.patch";
      url = "https://raw.githubusercontent.com/NixOS/nixpkgs/c987121acf5c87436a0b05ca75cd70bf38c452ca/pkgs/development/libraries/glib/quark_init_on_demand.patch";
      sha256 = "sha256-Kz5o56qfK6s2614UTpjEOFGQV+pU5KutzK//ZucPhTk=";
    })
    (fetchpatch {
      name = "gobject-init-on-demand.patch";
      url = "https://raw.githubusercontent.com/NixOS/nixpkgs/c987121acf5c87436a0b05ca75cd70bf38c452ca/pkgs/development/libraries/glib/gobject_init_on_demand.patch";
      sha256 = "sha256-LnKWzm88hQVpEt92XdE37R+GLVz78Sd4tztpTtKXuiU=";
    })
  ] ++ [
    # Fix build on Darwin
    # https://gitlab.gnome.org/GNOME/glib/-/merge_requests/2914
    (fetchpatch {
      name = "gio-properly-guard-use-of-utimensat.patch";
      url = "https://gitlab.gnome.org/GNOME/glib/-/commit/7f7171e68a420991b537d3e9e63263a0b2871618.patch";
      sha256 = "kKEqmBqx/RlvFT3eixu+NnM7JXhHb34b9NLRfAt+9h0=";
    })
    # https://gitlab.gnome.org/GNOME/glib/-/merge_requests/2921
    (fetchpatch {
      url = "https://gitlab.gnome.org/GNOME/glib/-/commit/f0dd96c28751f15d0703b384bfc7c314af01caa8.patch";
      sha256 = "sha256-8ucHS6ZnJuP6ajGb4/L8QfhC49FTQG1kAGHVdww/YYE=";
    })
  ];

  postPatch = ''
    substituteInPlace gio/gio-launch-desktop.c --replace "G_STATIC_ASSERT" "//G_STATIC_ASSERT"
    '';

  buildInputs = with cross.pkgs; [ pcre2 ];
  nativeBuildInputs = with pkgs.buildPackages; [ meson ninja pkg-config python3 ];
  propagatedBuildInputs = with cross.pkgs; [ libffi zlib ];
  depsBuildBuild = with cross.pkgs; [ buildPackages.stdenv.cc ];

  mesonFlags = [
    "-Diconv=libc"
    "-Dlibelf=disabled"
    "-Dlibmount=disabled"
    "-Dselinux=disabled"
    "-Dnls=disabled"
    "-Dglib_debug=disabled"
    "-Dxattr=false"
    "-Dglib_assert=false"
    "-Dglib_checks=false"
    "-Dtests=false"
  ];

  NIX_CFLAGS_COMPILE = toString [
    "-Wno-error=nonnull"
    # Default for release buildtype but passed manually because
    # we're using plain
    "-DG_DISABLE_CAST_CHECKS"
  ];

  DETERMINISTIC_BUILD = 1;

  passthru = {
    inherit flattenInclude;
  };

  meta = with lib; {
    description = "C library of programming buildings blocks";
    homepage    = "https://www.gtk.org/";
    license     = licenses.lgpl21Plus;
    platforms   = platforms.unix;

    longDescription = ''
      GLib provides the core application building blocks for libraries
      and applications written in C.  It provides the core object
      system used in GNOME, the main loop implementation, and a large
      set of utility functions for strings and common data structures.
    '';
  };
})
