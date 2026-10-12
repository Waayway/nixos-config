# Our own programs and their tooling, per system: packages, apps, checks and dev
# shells. Today only the Proxmox VM template; the fleet manager moved to its own
# flake (github:Waayway/lodestar, see docs/lodestar.md). Read top to bottom: every
# name is defined before it is used.
{ inputs }:
let
  # Base image for new Proxmox VMs (template/proxmox.nix).
  proxmoxTemplate = inputs.nixos-generators.nixosGenerate {
    system = "x86_64-linux";
    format = "proxmox";
    modules = [ ./template/proxmox.nix ];
  };
in
{
  packages.x86_64-linux.proxmox-template = proxmoxTemplate;
}
