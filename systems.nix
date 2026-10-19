# Every machine in this repo: NixOS and nix-darwin systems built from the host
# files in hosts/<category>/, plus the deploy-rs nodes. Read top to bottom:
# every name is defined before it is used.
{ inputs }:
let
  inherit (inputs) nixpkgs;
  inherit (nixpkgs) lib;

  version = "26.05";
  overlays = [ ];

  # Our helper functions (lib/), keyed by file name.
  tools = import ./lib { inherit lib; };

  # name -> host attrs (system, user, type, options, config, ...) from hosts/*/
  hosts = tools.discoverHosts { inherit lib; } ./hosts;

  isDarwinHost = host: lib.hasSuffix "darwin" host.system;
  nixosHosts = lib.filterAttrs (_: host: !(isDarwinHost host)) hosts;
  darwinHosts = lib.filterAttrs (_: host: isDarwinHost host) hosts;
  deployHosts = lib.filterAttrs (_: host: host ? deploy) hosts;

  # Shared arguments for the system builders in lib/.
  builderArgs = {
    inherit
      nixpkgs
      inputs
      version
      overlays
      tools
      ;
  };
  mkSystem = tools.mkSystem builderArgs;
  mkDarwin = tools.mkDarwin builderArgs;
  mkDeployNode = tools.mkDeployNode { inherit inputs; };

  nixosConfigurations = lib.mapAttrs mkSystem nixosHosts;
  darwinConfigurations = lib.mapAttrs mkDarwin darwinHosts;
  deployNodes = lib.mapAttrs (
    name: host: mkDeployNode name host nixosConfigurations.${name}
  ) deployHosts;
in
{
  inherit nixosConfigurations darwinConfigurations;
  deploy.nodes = deployNodes;
}
