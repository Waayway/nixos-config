{
  umport,
  lib,
  hostPlatform,
  ...
}:
let
  # Desktop and laptop-hardware modules apply to every workstation without an
  # enable switch; servers (`type = "server"`) skip them entirely: no Hyprland,
  # greetd autologin, X server, PipeWire, printing, Flatpak or power profiles
  # on a VM. A server that needs a GPU (e.g. media) sets that in its host file.
  workstationOnly = [
    ./desktop
    ./hardware/graphics.nix
    ./hardware/sound.nix
    ./hardware/printing.nix
    ./hardware/power-management.nix
    ./apps/flatpak.nix
  ];
in
{
  imports = umport {
    # Skip categories that don't exist (yet) so listing them is harmless.
    paths = builtins.filter builtins.pathExists [
      ./apps
      ./boot
      ./console
      ./darwin
      ./desktop
      ./development
      ./editor
      ./fleet
      ./gaming
      ./hardware
      ./locale
      ./networking
      ./nix
      ./packages
      ./secrets
      ./security
      ./shell
      ./system
      ./users
      ./vm-specific
    ];
    exclude = lib.optionals hostPlatform.isServer (builtins.filter builtins.pathExists workstationOnly);
    recursive = true;
    includeHome = false;
  };
}
