# Runs fleet-server (the dashboard + control plane) and writes its JSON config to
# /etc/fleet-server/config.json and the host list to /etc/fleet-server/hosts.json.
# Linux only.
{
  config,
  lib,
  pkgs,
  inputs,
  fleet,
  hostPlatform,
  ...
}:
let
  cfg = config.services.fleet-server;
  configPath = "/etc/fleet-server/config.json";
in
{
  options.services.fleet-server = {
    enable = lib.mkEnableOption "the fleet server (dashboard and control plane)";
    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.fleet-server;
      description = "The fleet-server package (with the dashboard embedded).";
    };
    listenAddress = lib.mkOption {
      type = lib.types.str;
      example = "100.92.102.84";
      description = ''
        The host's Tailscale IPv4 address. Required: with Tailscale access control the
        server refuses to listen on anything else.
      '';
    };
    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "TCP port of the dashboard.";
    };
    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/Waayway/nixos-config";
      description = "Git URL the server mirrors (read).";
    };
    pushUrl = lib.mkOption {
      type = lib.types.str;
      default = "git@github.com:Waayway/nixos-config";
      description = "Git remote the server pushes promotions to.";
    };
    deployKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        SSH deploy key (write access to pushUrl); a path outside the Nix store.
        The server runs as the `fleet-server` user, so the key must be readable by it,
        e.g. `sops.secrets.<name> = { owner = "fleet-server"; mode = "0400"; };` and
        `deployKeyFile = config.sops.secrets.<name>.path;`.
      '';
    };
    allowedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Waayway@github" ];
      description = "Tailscale logins allowed to use the dashboard.";
    };
    allowedTags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "tag:nixos"
        "tag:personal"
        "tag:fleet"
      ];
      description = "Tailscale node tags allowed to use the dashboard.";
    };
    testing = {
      staticAddresses = lib.mkOption {
        type = lib.types.nullOr (lib.types.attrsOf lib.types.str);
        default = null;
        description = "TEST ONLY (VM test): fixed host -> ip[:port] map instead of Tailscale reachability.";
      };
      disableAccess = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "TEST ONLY (VM test): disable dashboard access control.";
      };
      pollSecs = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "TEST ONLY (VM test): agent poll interval in seconds; null keeps the server default (60).";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.optionalAttrs hostPlatform.isLinux {
      users.users.fleet-server = {
        isSystemUser = true;
        group = "fleet-server";
        # ssh (StrictHostKeyChecking=accept-new) keeps its known_hosts under $HOME.
        home = "/var/lib/fleet-server";
      };
      users.groups.fleet-server = { };

      # Lets the unprivileged server use `tailscale status` / `tailscale whois`.
      services.tailscale.extraSetFlags = [ "--operator=fleet-server" ];

      # The firewall (modules/networking/firewall.nix) only opens 22; the dashboard is
      # reached over the tailnet.
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.listenPort ];

      environment.etc."fleet-server/hosts.json".text = builtins.toJSON fleet.hosts;
      environment.etc."fleet-server/config.json".text = builtins.toJSON (
        {
          listen = "${cfg.listenAddress}:${toString cfg.listenPort}";
          agent_port = config.services.fleet-agent.port;
          hosts_file = "/etc/fleet-server/hosts.json";
          repo_url = cfg.repoUrl;
          push_url = cfg.pushUrl;
          deploy_key_file = cfg.deployKeyFile;
          state_dir = "/var/lib/fleet-server";
          access =
            if cfg.testing.disableAccess then
              { kind = "disabled"; }
            else
              {
                kind = "tailscale";
                allowed_users = cfg.allowedUsers;
                allowed_tags = cfg.allowedTags;
              };
          online =
            if cfg.testing.staticAddresses != null then
              {
                kind = "static";
                addresses = cfg.testing.staticAddresses;
              }
            else
              { kind = "tailscale"; };
          tailscale_bin = "${config.services.tailscale.package}/bin/tailscale";
        }
        // lib.optionalAttrs (cfg.testing.pollSecs != null) { poll_secs = cfg.testing.pollSecs; }
      );

      systemd.services.fleet-server = {
        description = "Fleet server";
        wantedBy = [ "multi-user.target" ];
        after = [
          "tailscaled.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        environment.HOME = "/var/lib/fleet-server";
        path = with pkgs; [
          git
          openssh
          config.services.tailscale.package
        ];
        restartTriggers = [
          config.environment.etc."fleet-server/config.json".source
          config.environment.etc."fleet-server/hosts.json".source
        ];
        serviceConfig = {
          ExecStart = "${cfg.package}/bin/fleet-server serve --config ${configPath}";
          User = "fleet-server";
          Group = "fleet-server";
          StateDirectory = "fleet-server";
          # The tailnet address may not exist yet at boot: retry until it does.
          Restart = "on-failure";
          RestartSec = 5;
        };
      };
    }
  );
}
