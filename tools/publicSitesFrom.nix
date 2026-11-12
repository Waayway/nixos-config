# tools.publicSitesFrom { nixosConfigurations }
#
# Every configuration's public sites (`hosting.traefik.public.sites`, only where
# `hosting.traefik.enable` and `public.enable` are on), merged into one attrset keyed by
# site name, each site with an extra `declaredBy` (the configuration's name).
# Configurations without the option are skipped, so a site whose host leaves the flake or
# turns its public side off vanishes from the probes. Fails on a site name declared twice.
# Used as `tools.publicSitesFrom { inherit lib; } { … }` (`tools/default.nix` imports the
# file as-is).
{ lib }:
{
  nixosConfigurations ? { },
}:
let
  usable =
    c:
    c.config ? hosting
    && c.config.hosting ? traefik
    && c.config.hosting.traefik.enable
    && c.config.hosting.traefik.public.enable;

  perConfig = lib.mapAttrsToList (
    cname: c:
    lib.mapAttrs (_: s: {
      inherit (s) host probePaths;
      declaredBy = cname;
    }) c.config.hosting.traefik.public.sites
  ) (lib.filterAttrs (_: usable) nixosConfigurations);

  names = lib.concatMap lib.attrNames perConfig;
  duplicates = lib.unique (lib.filter (n: lib.count (m: m == n) names > 1) names);
in
assert lib.assertMsg (
  duplicates == [ ]
) "tools.publicSitesFrom: sites declared by more than one configuration: ${toString duplicates}";
lib.foldl' (a: b: a // b) { } perConfig
