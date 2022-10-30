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
