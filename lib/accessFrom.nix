# tools.accessFrom { nixosConfigurations }
#
# Every configuration's `homelab.access`, merged into one attrset keyed by app name,
# each with an extra `declaredBy` (the configuration's name). Configurations without
# the option are skipped. Fails (eagerly, even for a consumer that only reads
# attrNames) on an app declared by more than one configuration (naming them) and on a
# member missing from the declaring configuration's `homelab.people` (naming member
# and app); the checks live in `tools.accessProblems`. Used as `tools.accessFrom`
# (`lib/default.nix` imports the file as-is, so call it as
# `tools.accessFrom { inherit lib; } { … }`).
{ lib }:
{
  nixosConfigurations ? { },
}:
let
  problems = import ./accessProblems.nix { inherit lib; } { inherit nixosConfigurations; };
  withAccess = lib.filterAttrs (
    _: c: c.config ? homelab && c.config.homelab ? access && c.config.homelab ? people
  ) nixosConfigurations;
  access = lib.foldl' (a: b: a // b) { } (
    lib.mapAttrsToList (
      cname: c: lib.mapAttrs (_: a: a // { declaredBy = cname; }) c.config.homelab.access
    ) withAccess
  );
  show = lib.concatStringsSep "; ";
in
assert lib.assertMsg (problems.duplicates == { })
  "tools.accessFrom: apps declared by more than one configuration: ${
    show (lib.mapAttrsToList (n: cs: "${n} (${toString cs})") problems.duplicates)
  }";
assert lib.assertMsg (problems.unknownMembers == { })
  "tools.accessFrom: members missing from homelab.people: ${
    show (lib.mapAttrsToList (n: ms: "app '${n}' lists ${toString ms}") problems.unknownMembers)
  }";
access
