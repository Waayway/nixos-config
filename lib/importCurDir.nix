lib: dir:
map (n: _: toString dir + "/${n}") (
  lib.filterAttrs (name: _: (lib.strings.hasSuffix ".nix" name) && (name != "default.nix")) (
    builtins.readDir dir
  )
)
