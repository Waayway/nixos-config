{ ... }:
{
  imports = [
    ./boot.nix
    ./firewall.nix
    ./journald.nix
    ./openssh.nix
    ./resolved.nix
    ./sudo.nix
    ./tailscale.nix
    ./users.nix
    ./zram.nix
  ];
}
