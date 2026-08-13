{ inputs, ... }:
{
  imports = [
    inputs.nix-flatpak.nixosModules.nix-flatpak
  ];
  services.flatpak = {
    enable = true;
    packages = [
      "com.valvesoftware.SteamLink"
    ];
    update.auto = {
      enable = true;
      onCalendar = "weekly"; # Default value
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      # Steam link
      27036
      27037
    ];
    allowedUDPPorts = [
      # Steam link
      27031
      27036
    ];
  };
}
