# Evaluation check of `tools.accessFrom` over stub configurations built from
# modules/homelab/access-option.nix: declaredBy and defaults, duplicate apps failing
# (naming both configurations), unknown members failing (naming member and app), and
# configurations without the option skipped.
{
  pkgs,
  lib,
  tools,
}:
let
  accessFrom = tools.accessFrom { inherit lib; };
  stub =
    access:
    lib.evalModules {
      specialArgs = { inherit tools; };
      modules = [
        ../modules/homelab/access-option.nix
        {
          homelab.people.ann = {
            displayName = "Ann";
            email = "ann@example.com";
          };
          homelab.access = access;
        }
      ];
    };
  noOption = lib.evalModules {
    modules = [ { options.unrelated = lib.mkOption { default = 1; }; } ];
  };

  r = accessFrom {
    nixosConfigurations = {
      alpha = stub {
        a.members = [ "ann" ];
        o.oidc = {
          originUrls = [ "https://o.example.com/cb" ];
          originLanding = "https://o.example.com/";
        };
      };
      beta = stub { b.gate = true; };
      plain = noOption;
    };
  };
  dup = accessFrom {
    nixosConfigurations = {
      alpha = stub { dup = { }; };
      beta = stub { dup = { }; };
    };
  };
  unknown = accessFrom {
    nixosConfigurations.alpha = stub { app.members = [ "nobody" ]; };
  };
  ok = v: (builtins.tryEval (builtins.deepSeq v v)).success;
in
assert r.a.declaredBy == "alpha";
assert r.b.declaredBy == "beta";
assert r.a.members == [ "ann" ];
assert r.b.members == [ ];
assert r.a.oidc == null;
assert r.a.gate == false;
assert r.b.gate == true;
assert
  r.o.oidc.scopes == [
    "openid"
    "email"
    "profile"
    "groups"
  ];
assert
  lib.attrNames r == [
    "a"
    "b"
    "o"
  ];
assert !ok dup;
assert !ok unknown;
assert (stub { x.members = [ "ann" ]; }).config.homelab.people.ann.admin == false;
pkgs.runCommand "access-from" { } "touch $out"
