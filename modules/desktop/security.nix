{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    polkit_gnome
    ipmiview
  ];

  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;
  # gpg agent with pinentry
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false;
    settings.default-cache-ttl = 4 * 60 * 60; # 4 hours
  };
}
