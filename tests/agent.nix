# Evaluation check of iris, the Hermes Agent VM (modules/server/agent/,
# docs/plans/2026-11-09-iris-agent-design.md): Hermes on iris only, native mode, its
# state dir and unprivileged user.
{
  pkgs,
  lib,
  nixosConfigurations,
}:
let
  iris = nixosConfigurations.iris.config;
  others = lib.attrNames (lib.removeAttrs nixosConfigurations [ "iris" ]);
  h = iris.services.hermes-agent;
  secrets = iris.services.onepassword-secrets.secrets;
  fallback = lib.head h.settings.fallback_providers;
  router = nixosConfigurations.router.config;
  http = router.services.traefik.dynamicConfigOptions.http;
  kanidm = nixosConfigurations.identity.config.homelab.identity.provisionState;
  nas = nixosConfigurations.nixos-manager.config.truenas;
  backup = iris.systemd.services.hermes-backup;
  mount = iris.fileSystems."/var/lib/hermes-backup";
  render = iris.homelab.agent.secretsEnvScript;
  fwRule = "iptables -w -A nixos-fw -p tcp -s 10.0.10.110 --dport 9119 -j nixos-fw-accept";
in
assert iris.networking.hostName == "iris";
assert iris.homelab.agent.enable;
assert iris.services.hermes-agent.enable;
assert !iris.services.hermes-agent.container.enable;
assert iris.services.hermes-agent.stateDir == "/var/lib/hermes";
assert iris.services.hermes-agent.user == "hermes";
assert !(lib.elem "wheel" (iris.users.users.hermes.extraGroups or [ ]));
assert lib.all (n: !nixosConfigurations.${n}.config.services.hermes-agent.enable) others;
# models: ChatGPT plan first, free OpenRouter as fallback and for side tasks
assert h.settings.model.provider == "openai-codex";
assert fallback.provider == "openrouter" && lib.hasSuffix ":free" fallback.model;
assert h.settings.auxiliary.compression.provider == "openrouter";
assert h.settings.auxiliary.vision.provider == "openrouter";
# Discord: Thijs only, every message, cron output to the home channel
assert h.environment.DISCORD_ALLOWED_USERS == "137629736993030144";
assert h.environment.DISCORD_HOME_CHANNEL == "1569317421251039294";
assert h.environment.DISCORD_REQUIRE_MENTION == "false";
assert h.environment.DISCORD_IGNORE_NO_MENTION == "false";
assert !(h.environment ? DISCORD_ALLOW_ALL_USERS) && !(h.environment ? GATEWAY_ALLOW_ALL_USERS);
# no pay-per-token keys
assert !(h.environment ? ANTHROPIC_API_KEY) && !(h.environment ? OPENAI_API_KEY);
# secrets: read at unit start from a file rendered in /run (not copied into .env at
# activation, which runs before opnix has fetched them), never the store
assert h.environmentFiles == [ ];
assert lib.all
  (
    u:
    lib.elem "-/run/hermes-secrets/env" (
      lib.toList iris.systemd.services.${u}.serviceConfig.EnvironmentFile
    )
    && lib.elem "opnix-secrets.service" iris.systemd.services.${u}.after
  )
  [
    "hermes-agent"
    "hermes-backend"
  ];
assert lib.all (n: secrets.${n}.owner == "hermes" && secrets.${n}.mode == "0400") [
  "irisDiscord"
  "irisOpenrouter"
  "irisGrafana"
  "irisDashboardPassword"
  "irisDashboardSecret"
];
assert secrets.irisDiscord.reference == "op://Homelab/Iris Discord Bot Token/credential";
assert lib.all (n: secrets ? ${n}) [
  "irisOpenrouter"
  "irisGrafana"
  "irisDashboardPassword"
  "irisDashboardSecret"
];
# tools and the read-only homelab view
assert lib.all (n: lib.any (p: lib.getName p == n) h.extraPackages) [
  "claude-code"
  "codex"
  "git"
  "gh"
  "jq"
  "ripgrep"
];
assert h.environment.DISABLE_AUTOUPDATER == "1";
assert
  h.mcpServers ? grafana
  && !(lib.hasInfix "GRAFANA_SERVICE_ACCOUNT_TOKEN=" (builtins.toJSON h.mcpServers));
# dashboard on the LAN address, behind the router only
assert h.backend.mode == "dashboard" && h.backend.host == "10.0.10.101" && h.backend.port == 9119;
assert h.settings.dashboard.public_url == "https://agent.vanwaaij.com";
assert h.settings.dashboard.trusted_proxies == [ "10.0.10.110" ];
# dashboard route: tailnet only, behind the gate, Thijs only
assert http.services.agent.loadBalancer.servers == [ { url = "http://10.0.10.101:9119"; } ];
assert http.routers.agent-tailnet.rule == "Host(`agent.vanwaaij.com`)";
assert !(http.routers ? agent-public);
assert lib.any (lib.hasSuffix "-gate") http.routers.agent-tailnet.middlewares;
assert router.services.tailscale.serve.services ? agent;
assert kanidm.groups.agent-users.members == [ "thijs" ];
# port 9119 for the router only, not the whole LAN
assert !(lib.elem 9119 (iris.networking.firewall.interfaces.ens18.allowedTCPPorts or [ ]));
assert !(lib.elem 9119 iris.networking.firewall.allowedTCPPorts);
assert lib.hasInfix fwRule iris.networking.firewall.extraCommands;
# nightly state copy to TrueNAS store/internal/iris (snapshot 02:00, restic 02:30)
assert nas.nfsShares.iris.path == "/mnt/store/internal/iris";
assert nas.nfsShares.iris.hosts == [ "10.0.10.101" ];
assert mount.device == "10.0.10.130:/mnt/store/internal/iris";
assert !(lib.any (lib.hasPrefix "x-systemd.idle-timeout") mount.options);
assert iris.users.users.hermes.uid == 950;
assert iris.systemd.timers.hermes-backup.timerConfig.OnCalendar == "*-*-* 01:30";
assert lib.elem "/var/lib/hermes-backup" backup.unitConfig.RequiresMountsFor;
assert backup.serviceConfig.User == "hermes";
# a consistent copy of the SQLite files, not a raw copy of a live database
assert lib.hasInfix ".backup" backup.script && lib.hasInfix "--exclude" backup.script;
# a missing or odd secret stops the render with its name, instead of an empty value
# (or one systemd would unquote) in the env file
assert lib.all (n: lib.hasInfix "need ${n} " render) [
  "DISCORD_BOT_TOKEN"
  "OPENROUTER_API_KEY"
  "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"
  "HERMES_DASHBOARD_BASIC_AUTH_SECRET"
];
assert lib.hasInfix "[ -s " render && lib.hasInfix "A-Za-z0-9" render;
# tar's "file changed as we read it" (exit 1) doesn't fail the night
assert lib.hasInfix "--warning=no-file-changed" backup.script;
assert lib.hasInfix "[ $? -eq 1 ]" backup.script;
pkgs.runCommand "agent" { } "touch $out"
