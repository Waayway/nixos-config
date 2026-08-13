{ lib, ... }: {
  networking.networkmanager.enable = true;
  networking.firewall.enable = lib.mkDefault true;
  networking.useDHCP = lib.mkDefault true;
}
