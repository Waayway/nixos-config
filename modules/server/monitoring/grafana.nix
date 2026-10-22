# Grafana on the monitor VM (`homelab.monitoring.server.enable`): the dashboards on
# `https://grafana.vanwaaij.com` (tailnet only), signed in through Kanidm.
#
# - Listens on 0.0.0.0:3000; the port is open on the LAN interface (the router is the
#   client, like for the other services). State stays in /var/lib/grafana (root disk).
# - Sign-in: Kanidm OIDC client `grafana` (`homelab.access.grafana`, PKCE); normal
#   visits redirect straight to Kanidm (`auto_login`). `admins` (Kanidm group, people with admin = true) become Grafana Admin,
#   everyone else Viewer; Kanidm sends groups as SPNs (`admins@id.vanwaaij.com`) and the
#   path accepts both forms until a decoded token confirms which (docs/monitoring.md).
#   The client secret comes from 1Password `kanidm-oauth2-grafana`
#   (scripts/kanidm-oauth2-secret.sh grafana). The bootstrap admin `admin`
#   (`Homelab/grafana-admin`, field `password`; its field `secret-key` is Grafana's
#   encryption key) is the break-glass login at `/login?disableAutoLogin`
#   (the login form stays on for it).
# - Provisioned from Nix: data sources `prometheus` and `loki` (fixed uids, the
#   dashboards refer to them; Loki is one data source over every tenant, the host names
#   from the flake) and the dashboards in ./dashboards, read-only in the UI.
#
# Vendored dashboards (grafana.com, the revision downloaded from
# /api/dashboards/<id>/revisions/<rev>/download, only the data source references
# replaced by the uids above, JSON keys sorted):
#   node-exporter-full.json  1860  revision 45
#   proxmox.json            10347  revision 5
#   traefik.json            17346  revision 9
#   cadvisor.json           14282  revision 1
# Written here: overview.json (home dashboard) and logs.json.
{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
let
  cfg = config.homelab.monitoring.server;
  lan = config.homelab.lan;
  port = 3000;
  host = "grafana.vanwaaij.com";
  idHost = "id.vanwaaij.com";
  dashboards = ./dashboards;
  # Loki tenants (every monitored host), read by Grafana from this file.
  tenants = lib.concatStringsSep "|" (lib.attrNames cfg.hosts);
in
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lan.address != null;
        message = "Grafana on the monitor needs homelab.lan.address (the host file's netInterface.ip).";
      }
    ];

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = port;
          domain = host;
          root_url = "https://${host}/";
        };
        security = {
          admin_user = "admin";
          admin_password = "$__file{${cfg.secrets.grafanaAdminPassword}}";
          secret_key = "$__file{${cfg.secrets.grafanaSecretKey}}";
        };
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
        };
        dashboards.default_home_dashboard_path = "${dashboards}/overview.json";
        "auth.generic_oauth" = {
          enabled = true;
          name = "vanwaaij.com";
          auto_login = true;
          client_id = "grafana";
          client_secret = "$__file{${cfg.secrets.grafanaOidcSecret}}";
          scopes = "openid email profile groups";
          auth_url = "https://${idHost}/ui/oauth2";
          token_url = "https://${idHost}/oauth2/token";
          api_url = "https://${idHost}/oauth2/openid/grafana/userinfo";
          use_pkce = true;
          login_attribute_path = "preferred_username";
          allow_sign_up = true;
          role_attribute_strict = true;
          role_attribute_path = "(contains(groups[*], 'admins@${idHost}') || contains(groups[*], 'admins')) && 'Admin' || 'Viewer'";
        };
      };

      provision = {
        enable = true;
        datasources.settings = {
          apiVersion = 1;
          datasources = [
            {
              name = "Prometheus";
              uid = "prometheus";
              type = "prometheus";
              access = "proxy";
              url = "http://127.0.0.1:9090";
              isDefault = true;
            }
            {
              name = "Loki";
              uid = "loki";
              type = "loki";
              access = "proxy";
              url = "http://127.0.0.1:3100";
              jsonData.httpHeaderName1 = "X-Scope-OrgID";
              # Every tenant at once (Loki's multi_tenant_queries_enabled).
              secureJsonData.httpHeaderValue1 = "$__file{${pkgs.writeText "loki-tenants" tenants}}";
            }
          ];
        };
        dashboards.settings = {
          apiVersion = 1;
          providers = [
            {
              name = "homelab";
              type = "file";
              allowUiUpdates = false;
              options.path = dashboards;
            }
          ];
        };
      };
    };

    networking.firewall.interfaces.${lan.interface}.allowedTCPPorts = [ port ];

    homelab.routes.grafana = {
      inherit host;
      backend = "http://${lan.address}:${toString port}";
      public = false;
    };

    # Who may sign in: Kanidm group grafana-users. Role from `admins` (see above).
    homelab.access.grafana = {
      members = [ "thijs" ];
      oidc = {
        originUrls = [ "https://${host}/login/generic_oauth" ];
        originLanding = "https://${host}/";
        preferShortUsername = true;
        icon = ../identity/branding/icons/grafana.svg;
      };
    };

    lodestar.links.grafana = {
      title = "Grafana";
      group = "Infrastructure";
      description = "Dashboards and logs";
      icon = "grafana";
      url = "https://${host}";
      check.url = "http://${lan.address}:${toString port}/api/health";
    };
  };
}
