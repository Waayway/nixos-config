{
  config,
  lib,
  hostPlatform,
  ...
}:
# Hermes Agent (github.com/NousResearch/hermes-agent) on iris, from upstream's NixOS
# module in native mode (a systemd service, not its OCI container): a Discord bot for
# Thijs that thinks with his ChatGPT plan, falls back to free OpenRouter models and
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
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.agent.enable = lib.mkEnableOption "Hermes Agent (Discord bot)";

  config = lib.mkIf cfg.enable {
    services.hermes-agent = {
      enable = true;
      container.enable = false;
      user = "hermes";
      group = "hermes";
      stateDir = "/var/lib/hermes";
    };
  };
}
