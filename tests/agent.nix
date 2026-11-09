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
in
assert iris.networking.hostName == "iris";
assert iris.homelab.agent.enable;
assert iris.services.hermes-agent.enable;
assert !iris.services.hermes-agent.container.enable;
assert iris.services.hermes-agent.stateDir == "/var/lib/hermes";
assert iris.services.hermes-agent.user == "hermes";
assert !(lib.elem "wheel" (iris.users.users.hermes.extraGroups or [ ]));
assert lib.all (n: !nixosConfigurations.${n}.config.services.hermes-agent.enable) others;
pkgs.runCommand "agent" { } "touch $out"
