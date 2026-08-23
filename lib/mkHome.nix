homeManagerEnabled:
{
  isDarwin ? false,
  homeEntry ? ../modules/home.nix,
}:
user:
extraArgs@{ inputs, version, ... }:
let
  home-manager =
    if isDarwin then
      inputs.home-manager.darwinModules.home-manager
    else
      inputs.home-manager.nixosModules.home-manager;
in
{ lib, ... }:
{
  options.home-manager.enable = lib.mkEnableOption "Home Manager";

  imports = lib.optional homeManagerEnabled home-manager;

  config = lib.optionalAttrs homeManagerEnabled {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.extraSpecialArgs = extraArgs;
    home-manager.users.${user.name} =
      { ... }:
      {
        imports = [ homeEntry ];
        home.stateVersion = version;
      };
  };
}
