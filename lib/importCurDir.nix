lib: dir:
let
  isModule =
    name: type:
    (type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix")
    || (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"));
in
lib.mapAttrsToList (name: _: dir + "/${name}") (lib.filterAttrs isModule (builtins.readDir dir))
