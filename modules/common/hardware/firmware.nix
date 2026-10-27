{
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  # Redistributable firmware (GPU, Wi-Fi, Bluetooth, CPU microcode) on every Linux host.
  hardware.enableRedistributableFirmware = true;

  # Firmware update service
  services.fwupd.enable = true;
}
