# Evaluation check of the build cache wiring: the `cache` route on the router (tailnet
# only, no gate, Tailscale Service `cache`), the substituter on every Linux host except
# the cache VM itself, none on the Macs, and the Lodestar build gate values.
{
  pkgs,
  lib,
  nixosConfigurations,
  darwinConfigurations,
}:
let
  url = "https://cache.vanwaaij.com/nix";
  key = "cache.vanwaaij.com-1:bE8FtKeEuO/W0jmZ7IAsHdhu57jPgK6bLLZSdAUJx34=";
  s = n: nixosConfigurations.${n}.config.nix.settings;
  clients = lib.attrNames (lib.removeAttrs nixosConfigurations [ "cache" ]);
  router = nixosConfigurations.router.config;
  http = router.services.traefik.dynamicConfigOptions.http;
  lodestar = nixosConfigurations.nixos-manager.config;
in
assert lib.all (
  n:
  lib.elem url (s n).extra-substituters
  && lib.elem key (s n).extra-trusted-public-keys
  && (s n).fallback
  && (s n).connect-timeout == 5
) clients;
assert !((s "cache") ? extra-substituters) || !(lib.elem url (s "cache").extra-substituters);
assert !((s "cache").fallback or false);
assert lib.all (
  n: !(lib.elem url (darwinConfigurations.${n}.config.nix.settings.extra-substituters or [ ]))
) (lib.attrNames darwinConfigurations);
# route: tailnet only, not gated, served from the cache VM
assert http.services.nix-cache.loadBalancer.servers == [ { url = "http://10.0.10.171:80"; } ];
assert http.routers.nix-cache-tailnet.rule == "Host(`cache.vanwaaij.com`)";
assert !(http.routers ? nix-cache-public);
assert !(lib.any (lib.hasSuffix "-gate") http.routers.nix-cache-tailnet.middlewares);
assert router.services.tailscale.serve.services ? nix-cache;
# Lodestar build gate: on, building on the cache VM
assert lodestar.services.lodestar-server.builds.enable;
assert lodestar.services.lodestar-server.builds.store == "ssh-ng://lodestar@10.0.10.171";
assert
  lodestar.services.onepassword-secrets.secrets.lodestarBuilderKey.reference
  == "op://Homelab/lodestar-builder-key/private key?ssh-format=openssh";
assert lodestar.programs.ssh.knownHosts."10.0.10.171".publicKey != null;
pkgs.runCommand "cache" { } "touch $out"
