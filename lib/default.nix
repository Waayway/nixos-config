# Every file in lib/ as an attrset, keyed by file name: `lib/mkSystem.nix`
# becomes `builders.mkSystem`. Files are imported as-is (not called), so each
# builder keeps its own arguments. New files show up automatically.
#
# System builders, used by systems.nix as `builders`.
{ lib }:
lib.mapAttrs'
  (name: _: lib.nameValuePair (lib.removeSuffix ".nix" name) (import (./. + "/${name}")))
  (
    lib.filterAttrs (
      name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
    ) (builtins.readDir ./.)
  )
