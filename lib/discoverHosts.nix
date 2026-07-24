{ lib }:
hostsDir:
let
  entries = lib.mapAttrs (builtins.readDir hostsDir) (name: type: (builtins.readDir "/${name}"));

  isHostEntry =
    name: type:
    (type == "regular" && lib.hasSuffix ".nix" name)
    || (type == "directory" && builtins.pathExists (hostsDir + "/${name}/default.nix"));

  hostNameOf = name: type: if type == "regular" then lib.removeSuffix ".nix" name else name;

  hostPathOf = name: type: if type == "regular" then hostsDir + "/${name}" else hostsDir + "/${name}";

  validEntries = lib.filterAttrs isHostEntry entries;
in
lib.mapAttrs' (
  name: type: lib.nameValuePair (hostNameOf name type) (import (hostPathOf name type))
) validEntries
