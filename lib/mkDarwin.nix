{
  nixpkgs,
  overlays,
  inputs,
  version,
}:
name: hostAttrs:
let

  system = hostAttrs.system;
  user = hostAttrs.user;

  upkgs = import inputs.nixpkgs-unstable {
    inherit system;

    config.allowUnfree = true;
  };

  machineOptions = hostAttrs;
  hardware-profiles = machineOptions.hardware-profiles or [ ];
  isServer = machineOptions.isServer;
  isLaptop = machineOptions.isLaptop;

  colors = import ./color.nix { };

  machineConfig = machineOptions.config;

  baseConfig = ../modules/workstations/darwin;

  extraArgs = {
    inherit version;
    currentUser = user;
    currentSystem = system;
    currentSystemName = name;
    currentVersion = version;
    inputs = inputs;

    color = colors;

    isLaptop = isLaptop;
    hardware-profiles = hardware-profiles;

    hostPlatform = {
      isLinux = false;
      isDarwin = true;
      isFramework = false;
      isServer = false;
    };

    upkgs = upkgs; # Unstable pkgs

    user = user;

    umport = import ./umport.nix { lib = upkgs.lib; };
  };

  systemFunc = inputs.nix-darwin.lib.darwinSystem;

  homeManager =
    (import ./mkHome.nix {
      isDarwin = true;
      homeEntry = ../modules/workstations/darwin/home.nix;
    })
      user
      extraArgs;

in
systemFunc {
  inherit system;

  specialArgs = extraArgs;

  modules = [
    { config = machineOptions.options or { }; }
    {
      nixpkgs.overlays = overlays;
      nixpkgs.config.allowUnfree = true;
      nixpkgs.hostPlatform = system;
      system.stateVersion = 6;
      system.primaryUser = user.name;
    }

    baseConfig

    machineConfig

    inputs.sops-nix.darwinModules.sops

    (if !isServer then homeManager else { })
  ];
}
