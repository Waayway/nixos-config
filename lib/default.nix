# Every file in lib/ as an attrset, keyed by file name: `lib/mkAppCategory.nix`
# becomes `tools.mkAppCategory`. Files are imported as-is (not called), so each
# tool keeps its own arguments. New files show up automatically.
#
# systems.nix uses this for the builders; mkSystem/mkDarwin pass it to every
# module (and home-manager module) as the `tools` specialArg.
{ lib }:
lib.mapAttrs'
  (name: _: lib.nameValuePair (lib.removeSuffix ".nix" name) (import (./. + "/${name}")))
  (
    lib.filterAttrs (
      name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
    ) (builtins.readDir ./.)
  )
