{ umport, ... }:
{
  imports = [
    ./boot.nix
    ./user.nix
    ./networking.nix
  ]
  ++ umport {
    paths = [
      ./other
      ./gaming
      ./desktop
      ./terminal
      ./programming
      ./applications
    ];
    recursive = true;
    includeHome = false;
  };
}
