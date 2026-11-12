{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Hermes Agent (github.com/NousResearch/hermes-agent) on iris, from upstream's NixOS
# module in native mode (a systemd service, not its OCI container): a Discord bot for
# Thijs that thinks with his ChatGPT plan and
# hands coding to Claude Code on his Claude plan. Design:
# docs/plans/2026-11-09-iris-agent-design.md; runbook: docs/agent.md.
#
# State in /var/lib/hermes (.hermes/ is HERMES_HOME: config, memory, skills,
# sessions, auth.json). The ChatGPT and Claude logins are made by hand once on iris
# (docs/agent.md) and live there; they are OAuth tokens that rotate, not 1Password
# secrets. The `hermes` user has no sudo and no keys to other hosts: iris is the
# sandbox.
let
  cfg = config.homelab.agent;
  lan = config.homelab.lan;
  secretPaths = config.services.onepassword-secrets.secretPaths;

  host = "agent.vanwaaij.com";
  port = 9119;

  # mcp-grafana with the Viewer token read at start, so it stays out of config.yaml.
  grafanaMcp = pkgs.writeShellScript "mcp-grafana-iris" ''
    export GRAFANA_URL=https://grafana.vanwaaij.com
    GRAFANA_SERVICE_ACCOUNT_TOKEN="$(cat ${secretPaths.irisGrafana})"
    export GRAFANA_SERVICE_ACCOUNT_TOKEN
    exec ${pkgs.mcp-grafana}/bin/mcp-grafana "$@"
  '';

  # Headless Claude worker: use the pinned adapter from PATH, never runtime npx.
  # Keep the command name stable so acpx's session scope survives package upgrades.
  # Tool requests are approved without prompts, explicitly authorized for Iris.
  # This is an ACP approval policy, not an OS sandbox or global Claude setting.
  acpxClaude = pkgs.writeShellApplication {
    name = "acpx-claude";
    runtimeInputs = [
      pkgs.acpx
      pkgs.claude-agent-acp
    ];
    text = ''
      exec acpx --agent claude-agent-acp --approve-all "$@"
    '';
  };
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.agent.enable = lib.mkEnableOption "Hermes Agent (Discord bot)";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lan.address != null;
        message = "homelab.agent needs homelab.lan.address (the host file's netInterface.ip).";
      }
    ];

    # Make the coding tools available to ordinary shells as well as the service.
    environment.systemPackages = [
      pkgs._1password-cli
      pkgs.acpx
      pkgs.claude-agent-acp
      acpxClaude
    ];

    services.hermes-agent = {
      enable = true;
      container.enable = false;
      user = "hermes";
      group = "hermes";
      stateDir = "/var/lib/hermes";
      # The `hermes` CLI for every shell, with HERMES_HOME pointing at the gateway's
      # state: the logins (`sudo -u hermes -i hermes auth add …`) need it.
      addToSystemPackages = true;

      settings = {
        # Main: Thijs's Claude plan (Anthropic OAuth, logged in by hand: docs/agent.md).
        # Falls back to the ChatGPT plan (Codex OAuth) if Anthropic is unavailable. Both
        # are OAuth logins against a plan allowance, never a pay-per-token API key.
        model = {
          provider = "anthropic";
          default = "claude-sonnet-5-5";
        };
        fallback_providers = [
          {
            provider = "openai-codex";
            model = "gpt-6-sol";
          }
        ];
        # Behind the router (Traefik, Kanidm gate): the only peer whose forwarded
        # headers count, and the name the dashboard accepts as Host.
        dashboard = {
          public_url = "https://${host}";
          trusted_proxies = [ "10.0.10.110" ];
        };

        # The browser tools: the Chromium Hermes downloads is a generic-Linux binary that
        # NixOS cannot execute (stub-ld, exit 127), so point it at nixpkgs' ungoogled-chromium.
        browser.executable_path = lib.getExe pkgs.ungoogled-chromium;

        # Iris is a coding/ops agent on Discord, not a general assistant: trim the
        # bundled skill catalog down to the agent and software-development ones
        # (plus web's blocked-page-recovery and the creative claude-design skill
        # Thijs still wants) for Discord specifically, so the rest never load
        # into context there.
        skills.platform_disabled.discord = [
          "architecture-diagram"
          "ascii-video"
          "baoyu-infographic"
          "humanizer"
          "manim-video"
          "p5js"
          "popular-web-designs"
          "songwriting-and-ai-music"
          "document-to-action-items"
          "google-workspace"
          "maps"
          "meeting-action-items"
          "microsoft-office"
          "pdf"
          "product-price-monitor"
          "teams-meeting-pipeline"
          "weekly-review-planning"
          "arxiv"
          "competitor-news-monitor"
          "grounded-citations"
          "email-inbox-triage"
          "himalaya"
          "xurl"
          "youtube-content"
          "obsidian"
        ];
      };

      # Plain values (secrets: secrets.nix). Only Thijs; every message, no @mention.
      environment = {
        DISCORD_ALLOWED_USERS = "137629736993030144";
        DISCORD_HOME_CHANNEL = "1569317421251039294";
        DISCORD_REQUIRE_MENTION = "false";
        DISCORD_IGNORE_NO_MENTION = "false";
        # Reply in the channel, not in a new thread per message.
        DISCORD_AUTO_THREAD = "false";
        # Claude Code updates come with `nix flake update`.
        DISABLE_AUTOUPDATER = "1";
      };

      # Claude Code (Thijs's Claude plan, logged in by hand) and Codex for the bundled
      # claude-code / codex skills, plus the basics.
      extraPackages = with pkgs; [
        claude-code
        codex
        _1password-cli
        git
        gh
        jq
        ripgrep
        acpx
        claude-agent-acp
        acpxClaude
      ];

      # Read-only homelab: metrics, logs and alerts through Grafana.
      mcpServers.grafana.command = toString grafanaMcp;

      # The dashboard on the LAN address; the router is the only way in (route.nix).
      backend = {
        mode = "dashboard";
        host = lan.address;
        inherit port;
      };
    };
  };
}
