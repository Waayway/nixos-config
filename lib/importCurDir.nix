lib: dir:
lib.mapAttrs (n: v: (dir + "/${n}")) (
  lib.filterAttrs (name: _: (lib.strings.hasSuffix ".nix" name) && (name != "default.nix")) (
    builtins.readDir dir
  )
)
