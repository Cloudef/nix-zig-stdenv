{ lib, writeShellScript, wrapper, static }:

with lib;
with builtins;

rust-toolchain: host-cc: host: target-cc: target: let
  cc-wrapper = target: cc: writeShellScript "rust-cc-${target}" ''
      args=()
      for v in "$@"; do
        [[ "$v" == *self-contained/crt1.o ]] && continue
        [[ "$v" == *self-contained/crti.o ]] && continue
        [[ "$v" == *self-contained/crtn.o ]] && continue
        [[ "$v" == *self-contained/crtend.o ]] && continue
        [[ "$v" == *self-contained/crtbegin.o ]] && continue
        [[ "$v" == *self-contained/libc.a ]] && continue
        [[ "$v" == -lc ]] && continue
        [[ "$v" == -liconv ]] && continue
        args+=("$v")
      done
      export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache-${target}-rust"
      export ZIG_GLOBAL_CACHE_DIR="$ZIG_LOCAL_CACHE_DIR"
      if ! ${cc} "''${args[@]}"; then
        find "$ZIG_LOCAL_CACHE_DIR" -name libcompiler_rt.a | while read -r f; do
          rm -f "$f"; touch "$f"
        done
        ${cc} "''${args[@]}"
      fi
      '';

  rust-config = {
    target = rec {
      name = target;
      cargo = stringAsChars (x: if x == "-" then "_" else x) (toUpper name);
      # FIXME: libcompiler_rt.a removal for rust is a ugly hack that I eventually want to get rid of
      #        https://github.com/ziglang/zig/issues/5320
      linker = cc-wrapper target "${target-cc}/bin/${target}-cc";
      flags = if static then "-C target-feature=+crt-static" else "";
    };
    host = rec {
      name = host;
      cargo = stringAsChars (x: if x == "-" then "_" else x) (toUpper name);
      linker = cc-wrapper host "${host-cc}/bin/cc";
    };
  };
in wrapper [ rust-toolchain ] [
  {
    script = ''
      export CARGO_BUILD_TARGET=${rust-config.target.name}
      export CARGO_TARGET_${rust-config.host.cargo}_LINKER=${rust-config.host.linker}
      export CARGO_TARGET_${rust-config.target.cargo}_LINKER=${rust-config.target.linker}
      export CARGO_TARGET_${rust-config.target.cargo}_RUSTFLAGS="${rust-config.target.flags}"
      ${rust-toolchain}/bin/cargo "$@"
      '';
    path = "bin/cargo";
  }
  {
    script = ''${target-cc.bintools}/bin/strip "$@"'';
    path = "bin/strip";
  }
]

