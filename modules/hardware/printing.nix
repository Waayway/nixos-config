{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux ({
  # Enable CUPS for printing
  services.printing.enable = true;
})
