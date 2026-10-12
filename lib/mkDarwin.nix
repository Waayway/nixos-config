{
  nixpkgs,
  overlays,
  inputs,
  version,
  fleetHosts,
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
  type = machineOptions.type;
  isServer = type == "server";
  tags = machineOptions.tags or [ ];

  colors = import ./color.nix { };

  machineConfig = machineOptions.config;

  baseConfig = ../modules/system.nix;

  fleet = {
    member = machineOptions.fleet or false;
    channel =
      machineOptions.channel or (if machineOptions.category == "servers" then "stable" else "unstable");
    hosts = fleetHosts;
  };

  extraArgs = {
    inherit fleet;
    inherit version;
    currentUser = user;
    currentSystem = system;
    currentSystemName = name;
    currentVersion = version;
    inputs = inputs;

    color = colors;

    type = type;
    tags = tags;
    hardware-profiles = [ ];

    hostPlatform = {
      isLinux = false;
      isDarwin = true;
      isFramework = false;
      isServer = isServer;
    };

    upkgs = upkgs; # Unstable pkgs

    user = user;

    umport = import ./umport.nix { lib = upkgs.lib; };
    importCurDir = import ./importCurDir.nix upkgs.lib;
  };

  systemFunc = inputs.nix-darwin.lib.darwinSystem;

  homeManager =
    (import ./mkHome.nix (
      if machineOptions.options ? home-manager && machineOptions.options.home-manager ? enable then
        machineOptions.options.home-manager.enable
      else
        false
    ) { isDarwin = true; })
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
      system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or "unknown";
      system.stateVersion = 6;
      system.primaryUser = user.name;
    }

    baseConfig

    machineConfig

    inputs.sops-nix.darwinModules.sops
    homeManager
  ];
}
