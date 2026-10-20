# Defaults for the Lodestar server (dashboard and control plane) on the host that
# enables it (nixos-manager; its host file sets `enable` and `listenAddress`). The
# managed hosts are every configuration in this flake that runs the agent. NixOS only.
{
  config,
  lib,
  inputs,
  hostPlatform,
  ...
}:
let
  cfg = config.services.lodestar-server;
  publicHost = "lodestar.vanwaaij.com";
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf config.services.lodestar-server.enable {
    # The dashboard itself on its Services tab; not probed (it would only report itself).
    lodestar.links.lodestar = {
      title = "Lodestar";
      group = "Infrastructure";
      description = "Fleet manager";
      url = lib.mkDefault "https://${publicHost}";
      check.enable = false;
    };

    # The public URL: the router forwards `lodestar.vanwaaij.com` (public and tailnet,
    # not gated: Lodestar logs in with Kanidm itself) to the server's proxy listener,
    # which only the router may reach (trustedProxies; firewall in the Lodestar module).
    homelab.routes.lodestar = {
      host = publicHost;
      backend = "http://${cfg.proxyListen.address}:${toString cfg.proxyListen.port}";
    };

    # Kanidm's OAuth2 client (redirect, group `lodestar-users`, short user names).
    # Admins must be in `lodestar-users` too: the scope map is only for that group.
    homelab.access.lodestar = {
      members = [ "thijs" ];
      oidc = {
        originUrls = [ "https://${publicHost}/auth/callback" ];
        originLanding = "https://${publicHost}";
        preferShortUsername = true;
        scopes = [
          "openid"
          "profile"
          "groups"
        ];
      };
    };

    # The client secret, read by the server at each login (no service to restart).
    services.onepassword-secrets.secrets.kanidmOauth2Lodestar = {
      reference = "op://Homelab/kanidm-oauth2-lodestar/credential";
      owner = "lodestar-server";
      mode = "0400";
    };

    services.lodestar-server = {
      hosts = inputs.lodestar.lib.hostsFrom {
        inherit (inputs.self) nixosConfigurations darwinConfigurations;
      };
      # Services tab: every `lodestar.links` in the flake (service modules,
      # modules/homelab/links.nix).
      links = inputs.lodestar.lib.linksFrom {
        inherit (inputs.self) nixosConfigurations darwinConfigurations;
      };
      repoUrl = lib.mkDefault "https://github.com/Waayway/nixos-config";
      pushUrl = lib.mkDefault "git@github.com:Waayway/nixos-config";
      # Write deploy key for promote: open item, see docs/lodestar.md.
      deployKeyFile = lib.mkDefault null;
      allowedUsers = lib.mkDefault [ "Waayway@github" ];
      allowedTags = lib.mkDefault [
        "tag:nixos"
        "tag:personal"
        "tag:fleet"
      ];
      # promote keeps the module default: unstable -> stable.

      # Public URL behind the router (10.0.10.110), logging in with Kanidm.
      proxyListen.address = lib.mkDefault config.homelab.lan.address;
      trustedProxies = lib.mkDefault [ "10.0.10.110" ];
      publicUrl = lib.mkDefault "https://${publicHost}";
      oidc = {
        issuer = lib.mkDefault "https://id.vanwaaij.com/oauth2/openid/lodestar";
        clientSecretFile = lib.mkDefault config.services.onepassword-secrets.secretPaths.kanidmOauth2Lodestar;
        readerGroup = lib.mkDefault "lodestar-users@id.vanwaaij.com";
        adminGroup = lib.mkDefault "admins@id.vanwaaij.com";
      };
    };
  };
}
