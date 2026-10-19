# tools.accessFrom { nixosConfigurations }
#
# Every configuration's `homelab.access`, merged into one attrset keyed by app name,
# each with an extra `declaredBy` (the configuration's name). Configurations without
# the option are skipped. Fails on an app declared by more than one configuration
# (naming them) and on a member missing from the declaring configuration's
# `homelab.people` (naming member and app). Used as `tools.accessFrom`
# (`lib/default.nix` imports the file as-is, so call it as
# `tools.accessFrom { inherit lib; } { … }`).
{ lib }:
{
  nixosConfigurations ? { },
}:
let
  withAccess = lib.filterAttrs (
    _: c: c.config ? homelab && c.config.homelab ? access && c.config.homelab ? people
  ) nixosConfigurations;

  perConfig = lib.mapAttrsToList (
    cname: c:
    lib.mapAttrs (
      app: a:
      let
        unknown = lib.filter (m: !(c.config.homelab.people ? ${m})) a.members;
      in
      assert lib.assertMsg (unknown == [ ])
        "tools.accessFrom: app '${app}' (declared by ${cname}) lists members missing from homelab.people: ${toString unknown}";
      a // { declaredBy = cname; }
    ) c.config.homelab.access
  ) withAccess;

  declarers = lib.foldl' (
    acc: cname:
    lib.foldl' (a: n: a // { ${n} = (a.${n} or [ ]) ++ [ cname ]; }) acc (
      lib.attrNames withAccess.${cname}.config.homelab.access
    )
  ) { } (lib.attrNames withAccess);
  duplicates = lib.filterAttrs (_: cs: lib.length cs > 1) declarers;
in
assert lib.assertMsg (duplicates == { })
  "tools.accessFrom: apps declared by more than one configuration: ${
    lib.concatStringsSep "; " (lib.mapAttrsToList (n: cs: "${n} (${toString cs})") duplicates)
  }";
lib.foldl' (a: b: a // b) { } perConfig
