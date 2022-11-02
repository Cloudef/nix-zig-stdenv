# Zig based cross-compiling toolchain

##  Major known issues:

- Zig seems to randomly fail with parallel builds with 'error: unable to build ... CRT file: BuildingLibCObjectFailed'
  This seems like race condition with the cache?
  https://github.com/ziglang/zig/issues/13160
  https://github.com/ziglang/zig/issues/9711

- Rust and zig fight for the ownership of libcompiler_rt
  https://github.com/ziglang/zig/issues/5320

## Why zig for cross-compiling?

Zig can cross-compile out of the box to many target without having to bootstrap the whole cross-compiler and various libcs
This means builds are very fast

# TODO

- Generate meta.json with github actions
   - Collect information about which targets do not work
   - Rank zig versions and targets depending how well they do in tests
- Generate github actions workflow file from versions.json and zig targets output
- Provide `zigPkgs` set with packages maintained in this repo
   - Packages that need major restructuring to compile
   - Minimal versions of existing packages (we are mostly interested in libs only)
   - Packages that do not exist yet in nixpkgs
   - Namespaced for different platforms (c, rust, etc...)
   - Generally zigPkgs is expected to compile and work while pkgs from nixpkg can be hit and miss

For other stuff, run `things-to-do`
