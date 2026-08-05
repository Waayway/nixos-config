lib: dir:
let
  isModule =
    name: type:
    (type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix")
    || (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"));
in
lib.mapAttrs' (name: _: lib.nameValuePair (lib.removeSuffix ".nix" name) (dir + "/${name}")) (
  lib.filterAttrs isModule (builtins.readDir dir)
)
