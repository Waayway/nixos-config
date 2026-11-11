{
  user,
  hostPlatform,
  lib,
  ...
}:
# Read-only login for iris (Hermes Agent, VM 101) on every server. iris reaches it
# through Tailscale SSH (policy rule tag:iris -> tag:nixos as user `iris`), so no keys.
# Not in wheel: no sudo. systemd-journal lets it read every unit's logs; changes go
# through the nixos-config repo, never through this login. docs/agent.md
lib.optionalAttrs hostPlatform.isLinux {
  # iris's own host user is already called iris (and is in wheel); leave it alone.
  config = lib.mkIf (hostPlatform.isServer && user.name != "iris") {
    users.users.iris = {
      isNormalUser = true;
      description = "Iris (read-only)";
      extraGroups = [ "systemd-journal" ];
    };
  };
}
