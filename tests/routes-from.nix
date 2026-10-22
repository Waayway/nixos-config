# Evaluation check of `tools.routesFrom` over stub configurations built from
# modules/server/homelab/routes-option.nix: declaredBy and defaults, duplicate names and
# shared hosts failing, backend validation, and configurations without the option
# skipped.
{
  pkgs,
  lib,
  tools,
}:
let
  routesFrom = tools.routesFrom { inherit lib; };
  stub =
    routes:
    lib.evalModules {
      specialArgs = { inherit tools; };
      modules = [
        ../modules/server/homelab/routes-option.nix
        { homelab.routes = routes; }
      ];
    };
  noOption = lib.evalModules {
    modules = [ { options.unrelated = lib.mkOption { default = 1; }; } ];
  };
  route = host: {
    inherit host;
    backend = "http://10.0.10.1:80";
  };

  r = routesFrom {
    nixosConfigurations = {
      alpha = stub { a = route "a.example.com"; };
      beta = stub { b = route "b.example.com"; };
      plain = noOption;
    };
  };
  dup = routesFrom {
    nixosConfigurations = {
      alpha = stub { dup = route "x.example.com"; };
      beta = stub { dup = route "y.example.com"; };
    };
  };
  sameHost = routesFrom {
    nixosConfigurations = {
      alpha = stub { one = route "same.example.com"; };
      beta = stub { two = route "same.example.com"; };
    };
  };
  backend =
    b:
    (stub {
      x = (route "x.example.com") // {
        backend = b;
      };
    }).config.homelab.routes;
  ok = v: (builtins.tryEval (builtins.deepSeq v v)).success;
in
assert r.a.declaredBy == "alpha";
assert r.b.declaredBy == "beta";
assert r.a.public == true;
assert r.a.tailnet.enable == true;
assert r.a.basicAuth.usersFile == null;
assert r.a.middlewares == { };
assert
  lib.attrNames r == [
    "a"
    "b"
  ];
assert !ok dup;
assert !ok sameHost;
assert !ok (backend "javascript:x");
assert ok (backend "api@internal");
assert ok (backend "http://10.0.10.1:80");
pkgs.runCommand "routes-from" { } "touch $out"
