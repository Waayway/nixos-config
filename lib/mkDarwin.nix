{
  nixpkgs,
  overlays,
  inputs,
  version,
  tools,
  builders,
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

  colors = tools.color { };

  machineConfig = machineOptions.config;

  baseConfig = ../modules/system.nix;

  # Lodestar membership (modules/common/lodestar/): `fleet = true;` in the host file; the
  # channel defaults by folder (servers follow stable, workstations unstable).
  fleet = {
    member = machineOptions.fleet or false;
    channel =
      machineOptions.channel or (if machineOptions.category == "servers" then "stable" else "unstable");
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

    inherit tools;
    umport = builders.umport { lib = upkgs.lib; };
    importCurDir = builders.importCurDir upkgs.lib;
  };

  systemFunc = inputs.nix-darwin.lib.darwinSystem;

  homeManager =
    (builders.mkHome (
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

    inputs.opnix.darwinModules.default
    inputs.lodestar.darwinModules.default
    homeManager
  ];
}
