{ isDarwin ? false, homeEntry ? ../modules/workstations/home.nix }:
user:
extraArgs@{ inputs, version, ... }:
let
  home-manager =
    if isDarwin then
      inputs.home-manager.darwinModules.home-manager
    else
      inputs.home-manager.nixosModules.home-manager;
in
{ ... }: {
  imports = [ home-manager ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = extraArgs;
  home-manager.users.${user.name} = { ... }: {
    imports = [ homeEntry ];
    home.stateVersion = version;
  };
}
