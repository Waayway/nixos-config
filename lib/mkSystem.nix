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

    isServer = isServer;
    type = type;

    hardware-profiles = hardware-profiles;
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
