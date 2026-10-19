# Our own programs and their tooling, per system: packages, apps, checks and dev
# shells. Today only the Proxmox VM template; the fleet manager moved to its own
# flake (github:Waayway/lodestar, see docs/lodestar.md). Read top to bottom: every
# name is defined before it is used.
{ inputs }:
let
  inherit (inputs.nixpkgs) lib;
  tools = import ./lib { inherit lib; };
  # Base image for new Proxmox VMs (template/proxmox.nix).
  proxmoxTemplate = inputs.nixos-generators.nixosGenerate {
    system = "x86_64-linux";
    format = "proxmox";
    modules = [ ./template/proxmox.nix ];
  };
in
{
  packages.x86_64-linux.proxmox-template = proxmoxTemplate;

  # Evaluation check of tools.routesFrom (tests/routes-from.nix); the asserts run at
  # evaluation, so `nix eval .#checks.x86_64-linux.routes-from.drvPath` proves it
  # without a Linux builder.
  checks.x86_64-linux.routes-from = import ./tests/routes-from.nix {
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    inherit lib tools;
  };

  # Evaluation check of tools.accessFrom (tests/access-from.nix), same idea.
  checks.x86_64-linux.access-from = import ./tests/access-from.nix {
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    inherit lib tools;
  };

  # Evaluation check of the identity module on router-test (tests/identity.nix).
  checks.x86_64-linux.identity = import ./tests/identity.nix {
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    inherit lib;
    inherit (inputs.self) nixosConfigurations;
  };
}
