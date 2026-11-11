{
  config,
  lib,
  hostPlatform,
  ...
}:
# direnv + nix-direnv on iris: each project under /var/lib/hermes/workspace/repos
# declares its own packages in a `flake.nix` (or shell.nix) plus an `.envrc` with
# `use flake`, instead of this repo installing toolchains system-wide. nix-direnv caches
# the dev shell and keeps it from being garbage collected. A project's .envrc stays
# blocked until `direnv allow` (no directory is trusted in advance). The agent's tool
# shells are not interactive, so they enter a project with `direnv exec <dir> <cmd>`.
# Runbook: docs/agent.md.
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf config.homelab.agent.enable {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
