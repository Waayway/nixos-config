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
  type = machineOptions.type;
  isServer = machineOptions.type == "server";
  tags = machineOptions.tags or [ ];

  colors = import ./color.nix { };

  machineConfig = machineOptions.config;

  baseConfig = ../modules/system.nix;

  extraArgs = {
    inherit version;
    currentUser = user;
    currentSystem = system;
    currentSystemName = name;
    currentVersion = version;
    inputs = inputs;

    color = colors;

    type = type;
    serverOptions = {
      useDefaultHardware = machineOptions.useDefaultHardware;
      isHomeServer = machineOptions.isHomeServer;
      netInterface = machineOptions.netInterface;
    };

    tags = tags;

    upkgs = upkgs; # Unstable pkgs

    user = user;

    hostPlatform = {
      isLinux = true;
      isDarwin = false;
      isFramework = nixpkgs.lib.strings.hasPrefix "framework" type;
      isServer = isServer;
    };

    umport = import ./umport.nix { lib = upkgs.lib; };
    importCurDir = import ./importCurDir.nix upkgs.lib;
  };

  systemFunc = nixpkgs.lib.nixosSystem;

  homeManager = (import ./mkHome.nix { }) user extraArgs;

in
systemFunc rec {
  inherit system;

  specialArgs = extraArgs;

  modules = [
    { config = machineOptions.options or { }; }
    {
      nixpkgs.overlays = overlays;
      nixpkgs.config.allowUnfree = true;
      nixpkgs.hostPlatform = system;
      system.stateVersion = version;
      networking.hostName = name;
    }

    baseConfig

    machineConfig

    inputs.sops-nix.nixosModules.sops
  ]
  ++ (if !isServer then [ homeManager ] else [ ]);
}
