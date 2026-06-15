{ ... }:
{
  imports = [
    ./nix.nix
    ./locale.nix
    ./console.nix
    ./openssh.nix
    ./packages.nix
    ./framework.nix
    ./sops.nix
  ];
}
