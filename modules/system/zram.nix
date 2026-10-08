{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux ({
  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;
})
