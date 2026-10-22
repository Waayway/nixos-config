# tools.accessProblems { inherit lib; } { nixosConfigurations }
#
# The validation behind `tools.accessFrom`, as plain data so tests can assert on it:
#   { duplicates = { <app> = [ <configuration> … ]; };      # apps declared more than once
#     unknownMembers = { <app> = [ <member> … ]; }; }       # members missing from the
#                                                           # declaring configuration's people
{ lib }:
{
  nixosConfigurations ? { },
}:
let
  withAccess = lib.filterAttrs (
    _: c: c.config ? homelab && c.config.homelab ? access && c.config.homelab ? people
  ) nixosConfigurations;

  declarers = lib.foldl' (
    acc: cname:
    lib.foldl' (a: n: a // { ${n} = (a.${n} or [ ]) ++ [ cname ]; }) acc (
      lib.attrNames withAccess.${cname}.config.homelab.access
    )
  ) { } (lib.attrNames withAccess);

  unknownPerConfig = lib.mapAttrsToList (
    _: c:
    lib.filterAttrs (_: u: u != [ ]) (
      lib.mapAttrs (
        _: a: lib.filter (m: !(c.config.homelab.people ? ${m})) a.members
      ) c.config.homelab.access
    )
  ) withAccess;
in
{
  duplicates = lib.filterAttrs (_: cs: lib.length cs > 1) declarers;
  unknownMembers = lib.foldl' (a: b: a // b) { } unknownPerConfig;
}
