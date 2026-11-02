# The fleet's binary cache (docs/lodestar.md, "Build cache"). Linux only; the cache VM
# itself skips it: it would wait on its own nginx while building what it publishes.
{
  config,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (!config.services.lodestar-cache.enable) {
    nix.settings = {
      extra-substituters = [ "https://cache.vanwaaij.com/nix" ];
      extra-trusted-public-keys = [ "cache.vanwaaij.com-1:bE8FtKeEuO/W0jmZ7IAsHdhu57jPgK6bLLZSdAUJx34=" ];
      connect-timeout = 5;
      # Required: without it a timed-out substituter fails the build instead of
      # falling back to building (found by the VM test).
      fallback = true;
    };
  };
}
