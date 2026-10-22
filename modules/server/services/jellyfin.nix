{
  config,
  lib,
  hostPlatform,
  ...
}:
# Jellyfin from the official image, jellyfin/jellyfin:10.11. Follows the Docker
# section of Jellyfin's container install docs (jellyfin.org/docs, "Container",
# Docker compose example) and media's container today (`docker inspect jellyfin` on
# 10.0.10.120): `--user 1000:1000` (the owner of the config on TrueNAS), `configDir`
# at /config, a cache at /cache, the library /archive/jellyfin read-only at /media,
# port 8096. With `gpu`: /dev/dri and the render/video groups (Intel Arc A380,
# QSV/VA-API through the image's jellyfin-ffmpeg and iHD), as media does with the
# card it has now.
let
  cfg = config.homelab.jellyfin;
  lan = config.homelab.lan;
  host = "jellyfin.vanwaaij.com";
  port = 8096;
  cache = "/var/cache/jellyfin";
  image = "jellyfin/jellyfin:10.11";
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin (container)";
    live = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Serve the public host; off, it shows the maintenance page.";
    };
    configDir = lib.mkOption {
      type = lib.types.str;
      example = "/store/jellyfin/config";
      description = "The container's /config directory (data, config and logs), owned by 1000:1000.";
    };
    gpu = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Hardware transcoding on the passed-through Intel Arc A380 (/dev/dri, QSV/VA-API).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lan.address != null;
        message = "homelab.jellyfin needs homelab.lan.address (the host file's netInterface.ip).";
      }
    ];

    homelab.containers = {
      enable = true;
      floating = [ image ];
      intelGpu = lib.mkIf cfg.gpu true;
    };

    virtualisation.oci-containers.containers.jellyfin = {
      inherit image;
      user = "1000:1000";
      networks = [ "jellyfin" ];
      ports = [ "${lan.address}:${toString port}:${toString port}" ];
      volumes = [
        "${cfg.configDir}:/config"
        "${cache}:/cache"
        "/archive/jellyfin:/media:ro"
      ];
      environment = {
        JELLYFIN_PublishedServerUrl = "https://${host}";
      }
      // lib.optionalAttrs (config.time.timeZone != null) { TZ = config.time.timeZone; };
      devices = lib.optional cfg.gpu "/dev/dri:/dev/dri";
      extraOptions = lib.optionals cfg.gpu [
        "--group-add=${toString config.users.groups.render.gid}"
        "--group-add=${toString config.users.groups.video.gid}"
      ];
    };

    systemd.tmpfiles.settings.jellyfin.${cache}.d = {
      mode = "0750";
      user = "1000";
      group = "1000";
    };

    networking.firewall.interfaces.${lan.interface}.allowedTCPPorts = [ port ];

    homelab.routes.jellyfin = {
      inherit host;
      backend = "http://${lan.address}:${toString port}";
      maintenance = !cfg.live;
    };

    # Who may sign in (Kanidm group jellyfin-users), and "Log in with vanwaaij.com" in
    # the browser through the SSO plugin (9p4/jellyfin-plugin-sso, provider `kanidm`).
    # The plugin and its configuration are Jellyfin state, not Nix: installed by hand
    # into ${cfg.configDir}/plugins/SSO-Auth_<version>, configured in
    # plugins/configurations/SSO-Auth.xml (issuer https://id.vanwaaij.com/oauth2/openid/jellyfin,
    # client `jellyfin`, secret from 1Password `kanidm-oauth2-jellyfin`, user name
    # `preferred_username`, roles from `groups`: admins → administrator), the login
    # link in config/branding.xml (LoginDisclaimer). Existing Jellyfin users are tied
    # to Kanidm names by the plugin's CanonicalLinks (thijs → Thijs). TV and phone apps
    # keep password and Quick Connect. The plugin's start path `/sso/OID/start/kanidm`
    # redirects back to `/redirect/`; the legacy `/p/` to `/r/`.
    homelab.access.jellyfin = {
      members = [
        "thijs"
        "arie"
      ];
      oidc = {
        originUrls = [
          "https://${host}/sso/OID/redirect/kanidm"
          "https://${host}/sso/OID/r/kanidm"
        ];
        originLanding = "https://${host}/";
        icon = ../identity/branding/icons/jellyfin.svg;
        preferShortUsername = true;
      };
    };

    lodestar.links.jellyfin = {
      title = "Jellyfin";
      group = "Media";
      description = "Media server";
      icon = "jellyfin";
      url = "https://${host}";
      check.url = "http://${lan.address}:${toString port}/health";
    };
  };
}
