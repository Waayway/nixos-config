{
  config,
  lib,
  ...
}:
# Packages a service module needs although nixpkgs marks them insecure (an EOL major
# kept on purpose until a migration). `nixpkgs.config` doesn't merge lists or
# predicates across modules, so they are collected here into one predicate.
let
  allowed = config.homelab.insecurePackages;
in
{
  options.homelab.insecurePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "nextcloud-32." ];
    description = ''
      Prefixes of `<name>-<version>` allowed although marked insecure, e.g.
      `"nextcloud-32."` for every 32.x release.
    '';
  };

  config = lib.mkIf (allowed != [ ]) {
    nixpkgs.config.allowInsecurePredicate =
      pkg: lib.any (p: lib.hasPrefix p "${lib.getName pkg}-${lib.getVersion pkg}") allowed;
  };
}
