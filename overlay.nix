{ zig ? null, static ? true, allowBroken ? false } @args:

with builtins;

pkgs: super: with pkgs.lib; let
  utils = import ./src/utils.nix { inherit (pkgs) lib; };
  versions = import ./versions.nix { inherit pkgs; };
  zig = if args ? zig then args.zig else super.zig;

  gen-targets = zig: let
    zig-targets = with pkgs; (fromJSON (readFile (runCommandLocal "targets" {} ''${zig}/bin/zig targets > $out''))).libc;
    broken = [
      # Not supported by nixpkgs/systems/parse.nix
      "csky-unknown-linux-gnueabi"
      "csky-unknown-linux-gnueabihf"
      "x86_64-unknown-linux-gnux32"
      "armeb-unknown-linux-gnueabi"
      "armeb-unknown-linux-musleabi"
      "armeb-unknown-linux-gnueabihf"
      "armeb-unknown-linux-musleabihf"
      "armeb-w64-mingw32"
    ];
  in filter (x: !(any (y: x == y) broken)) (map utils.zigTargetToNixTarget zig-targets);

  gen-cross = zig: let
    broken-targets = let
      version = if zig.isMasterBuild then "master" else zig.version;
    in with pkgs; (fromJSON (readFile ./meta/broken-targets.json))."${version}" or [];
    broken = [] ++ optionals (!allowBroken) (broken-targets);
    targets = gen-targets zig;
    static-targets = map (t: "${t}-static") (filter utils.supportsStatic targets);
    import-target = target: let
      set = (import ./default.nix {
        inherit pkgs zig;
        inherit (pkgs) config overlays;
        static = hasSuffix "-static" target;
        target = removeSuffix "-static" target;
      });
    in { inherit (set) pkgs; };
  in genAttrs (filter (x: !(any (y: x == y) broken)) (targets ++ static-targets)) import-target;
in {
  zigCross = gen-cross zig;
  zigVersions = mapAttrs (k: v: {
    zig = v;
    targets = gen-cross v;
  }) (versions // { default = super.zig; });
}
