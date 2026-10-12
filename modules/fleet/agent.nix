# Installs and runs fleet-agent (systemd on Linux, launchd on darwin) and
# writes its JSON config to /etc/fleet-agent/config.json.
{
  config,
  lib,
  pkgs,
  inputs,
  fleet,
  user,
  currentSystemName,
  hostPlatform,
  ...
}:
let
  cfg = config.services.fleet-agent;
  configPath = "/etc/fleet-agent/config.json";
  daemonPath = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  exe = "${cfg.package}/bin/fleet-agent";
in
{
  options.services.fleet-agent = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = fleet.member;
      description = "Run the fleet agent (default: whether this host is a fleet member).";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 7461;
      description = "TCP port the agent listens on.";
    };
    managerHost = lib.mkOption {
      type = lib.types.str;
      default = "nixos-manager";
      description = "Tailscale host name of the fleet manager.";
    };
    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/Waayway/nixos-config";
      description = "Git URL the agent fetches the flake from.";
    };
    flakePath = lib.mkOption {
      type = lib.types.str;
      default =
        if hostPlatform.isDarwin then "/Users/${user.name}/.flake" else "/home/${user.name}/.flake";
      description = "Checkout of the flake on this host.";
    };
    rebuildCommand = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = "Override the rebuild command (tests only).";
    };
    revisionCommand = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = "Override the running-revision command (tests only).";
    };
    listen = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Explicit ip:port to bind; null means the Tailscale address.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.fleet-agent;
      description = "The fleet-agent package.";
    };
    ctlPackage = lib.mkOption {
      type = lib.types.package;
      default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.fleetctl;
      description = "The fleetctl CLI, installed on every enrolled host.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [ cfg.ctlPackage ];
        environment.etc."fleet-agent/config.json".text = builtins.toJSON {
          host = currentSystemName;
          user = user.name;
          channel = fleet.channel;
          flake_path = cfg.flakePath;
          repo_url = cfg.repoUrl;
          inherit (cfg) port;
          manager_host = cfg.managerHost;
          inherit (cfg) listen;
          state_dir = "/var/lib/fleet-agent";
          rebuild_command = cfg.rebuildCommand;
          launcher = if hostPlatform.isDarwin then "detach" else "systemd_run";
          os = if hostPlatform.isDarwin then "darwin" else "linux";
          agent_exe = null;
          revision_command = cfg.revisionCommand;
        };
      }
      (lib.optionalAttrs hostPlatform.isLinux {
        # The firewall (modules/networking/firewall.nix) only opens 22; the manager
        # reaches the agent over the tailnet.
        networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.port ];
        systemd.services.fleet-agent = {
          description = "Fleet agent";
          wantedBy = [ "multi-user.target" ];
          after = [
            "tailscaled.service"
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          environment.PATH = lib.mkForce daemonPath;
          serviceConfig = {
            ExecStart = "${exe} serve --config ${configPath}";
            StateDirectory = "fleet-agent";
            Restart = "always";
            RestartSec = 5;
          };
          # The apply runs in its own transient unit, so a restart of this one
          # (e.g. by the activation it triggers) does not kill it.
        };
      })
      (lib.optionalAttrs hostPlatform.isDarwin {
        launchd.daemons.fleet-agent.serviceConfig = {
          ProgramArguments = [
            exe
            "serve"
            "--config"
            configPath
          ];
          RunAtLoad = true;
          KeepAlive = true;
          AbandonProcessGroup = true;
          EnvironmentVariables = {
            PATH = daemonPath;
            HOME = "/var/root";
          };
          StandardOutPath = "/var/log/fleet-agent.log";
          StandardErrorPath = "/var/log/fleet-agent.log";
        };
        system.activationScripts.postActivation.text = ''
          mkdir -p /var/lib/fleet-agent
        '';
      })
    ]
  );
}
