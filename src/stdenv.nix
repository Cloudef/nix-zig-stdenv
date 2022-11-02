{ path, mk-zig-toolchain, native-toolchain ? null, targetPkgs ? null, libc ? null }: { lib, localSystem, crossSystem, config, overlays, crossOverlays ? [] }:

with lib;

let
  # XXX: Zig doesn't support response file. Nixpkgs wants to use this for clang
  #      while zig cc is basically clang, it's still not 100% compatible.
  #      Probably should report this as a bug to zig upstream though.
  zig-prehook = prelude: targetSystem: ''
    ${prelude}
    export NIX_CC_USE_RESPONSE_FILE=0
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache-${targetSystem.config}"
    export ZIG_GLOBAL_CACHE_DIR="$ZIG_LOCAL_CACHE_DIR"
  '';

  bootStages = import "${path}/pkgs/stdenv" {
    inherit lib localSystem overlays;
    crossSystem = localSystem;
    crossOverlays = [];
    # Ignore custom stdenvs when cross compiling for compatability
    config = builtins.removeAttrs config [ "replaceStdenv" ];
  };
in lib.init bootStages ++ [
  (somePrevStage: lib.last bootStages somePrevStage // { allowCustomOverrides = true; })

  # First replace native compiler with zig
  # This gives us more deterministic environment
  (buildPackages: let
  in {
    inherit config overlays;
    selfBuild = false;
    stdenv = (buildPackages.stdenv.override (old: rec {
      targetPlatform = crossSystem;
      allowedRequisites = null;
      hasCC = true;
      cc = native-toolchain;
      preHook = zig-prehook old.preHook localSystem;
      # Propagate everything to the next step as we do not need to bootstrap
      # We exclude packages that would break nixpkg's cross-compiling setup
      overrides = self: super: genAttrs (filter (a: ! any (b: hasPrefix b a) [
        "callPackage" "newScope" "pkgs" "stdenv" "system" "wrapBintools" "wrapCC"
      ]) (attrNames buildPackages)) (x: buildPackages."${x}");
    }));
    allowCustomOverrides = true;
  })

  # Then use zig as a cross-compiler as well
  (buildPackages: let
    adaptStdenv = if crossSystem.isStatic then buildPackages.stdenvAdapters.makeStatic else id;
  in {
    inherit config;
    overlays = overlays ++ crossOverlays;
    selfBuild = false;
    stdenv = adaptStdenv (buildPackages.stdenv.override (old: rec {
      buildPlatform = localSystem;
      hostPlatform = crossSystem;
      targetPlatform = crossSystem;

      # Prior overrides are surely not valid as packages built with this run on
      # a different platform, and so are disabled.
      overrides = _: _: {};
      allowedRequisites = null;
      hasCC = true;
      cc = mk-zig-toolchain {
        inherit (buildPackages) wrapCCWith wrapBintoolsWith;
        inherit (buildPackages.stdenvNoCC) mkDerivation;
        inherit targetPkgs libc;
        targetSystem = crossSystem;
      };
      preHook = zig-prehook old.preHook crossSystem;

      extraNativeBuildInputs = with buildPackages; old.extraNativeBuildInputs
      ++ lib.optionals
           (hostPlatform.isLinux && !buildPlatform.isLinux)
           [ patchelf ]
      ++ lib.optional
           (let f = p: !p.isx86 || builtins.elem p.libc [ "musl" "wasilibc" "relibc" ] || p.isiOS || p.isGenode;
             in f hostPlatform && !(f buildPlatform) )
           updateAutotoolsGnuConfigScriptsHook
         # without proper `file` command, libtool sometimes fails
         # to recognize 64-bit DLLs
      ++ lib.optional (hostPlatform.config == "x86_64-w64-mingw32") file;
    }));
  })
]
