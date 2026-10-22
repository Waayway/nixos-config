# Every file in tools/ as an attrset, keyed by file name: `tools/mkAppCategory.nix`
# becomes `tools.mkAppCategory`. Files are imported as-is (not called), so each
# tool keeps its own arguments. New files show up automatically.
#
# Helpers for modules, the `tools` specialArg (mkSystem/mkDarwin pass it to every
# module and home-manager module).
{ lib }:
lib.mapAttrs'
  (name: _: lib.nameValuePair (lib.removeSuffix ".nix" name) (import (./. + "/${name}")))
  (
    lib.filterAttrs (
      name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
    ) (builtins.readDir ./.)
  )
