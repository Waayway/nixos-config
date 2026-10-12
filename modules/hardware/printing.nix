{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux {
  # Workstation-only: skipped on servers (type = "server").
  config = lib.mkIf (!hostPlatform.isServer) {
    # Enable CUPS for printing
    services.printing.enable = true;
  };
}
