# tools.routesFrom { nixosConfigurations }
#
# Every configuration's `homelab.routes`, merged into one attrset keyed by route name,
# each route with an extra `declaredBy` (the configuration's name). Configurations
# without the option are skipped. Fails on a route name declared twice or a host used
# by two routes. Used as `tools.routesFrom` (`lib/default.nix` imports the file as-is,
# so call it as `tools.routesFrom { inherit lib; } { … }`).
{ lib }:
{
  nixosConfigurations ? { },
}:
let
  perConfig = lib.mapAttrsToList (
    cname: c: lib.mapAttrs (_: r: r // { declaredBy = cname; }) c.config.homelab.routes
  ) (lib.filterAttrs (_: c: c.config ? homelab && c.config.homelab ? routes) nixosConfigurations);

  counts = lib.foldl' (
    acc: rs: lib.foldl' (a: n: a // { ${n} = (a.${n} or 0) + 1; }) acc (lib.attrNames rs)
  ) { } perConfig;
  duplicates = lib.attrNames (lib.filterAttrs (_: n: n > 1) counts);

  routes = lib.foldl' (a: b: a // b) { } perConfig;

  byHost = lib.groupBy (n: routes.${n}.host) (lib.attrNames routes);
  sharedHosts = lib.filterAttrs (_: ns: lib.length ns > 1) byHost;
in
assert lib.assertMsg (
  duplicates == [ ]
) "tools.routesFrom: routes declared by more than one configuration: ${toString duplicates}";
assert lib.assertMsg (sharedHosts == { })
  "tools.routesFrom: hosts used by more than one route: ${
    lib.concatStringsSep "; " (lib.mapAttrsToList (h: ns: "${h} (${toString ns})") sharedHosts)
  }";
routes
