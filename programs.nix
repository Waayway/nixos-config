# Our own programs and their tooling, per system: packages, apps, checks and
# dev shells (the fleet manager in pkgs/fleet, the Proxmox VM template, the
# fleet VM test). Read top to bottom: every name is defined before it is used.
{ inputs, nixosConfigurations }:
let
  inherit (inputs) nixpkgs;
  inherit (nixpkgs) lib;

  systems = [
    "aarch64-darwin"
    "x86_64-linux"
    "aarch64-linux"
  ];

  # Calls `f { pkgs, fleet }` for every system: { <system> = f ...; }.
  forEachSystem =
    f:
    lib.genAttrs systems (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      f {
        inherit pkgs;
        fleet = import ./pkgs/fleet {
          inherit pkgs;
          inherit (inputs) crane;
        };
      }
    );

  linuxPkgs = nixpkgs.legacyPackages.x86_64-linux;

  # Base image for new Proxmox VMs (template/proxmox.nix).
  proxmoxTemplate = inputs.nixos-generators.nixosGenerate {
    system = "x86_64-linux";
    format = "proxmox";
    modules = [ ./template/proxmox.nix ];
  };

  # Evaluation-time check: the NixOS firewall only opens 22, so the fleet
  # modules must open the agent and dashboard ports on tailscale0.
  fleetFirewallCheck =
    let
      ports =
        nixosConfigurations.nixos-manager.config.networking.firewall.interfaces.tailscale0.allowedTCPPorts;
    in
    assert lib.assertMsg (
      builtins.elem 7461 ports && builtins.elem 8080 ports
    ) "nixos-manager must open 7461 and 8080 on tailscale0 (has ${builtins.toJSON ports})";
    linuxPkgs.runCommand "fleet-firewall" { } "touch $out";

  # Server, two agents and a git remote in VMs. Needs an x86_64-linux builder
  # with KVM (nixos-manager, see AGENTS.md).
  fleetVmTest = import ./tests/fleet-vm.nix {
    pkgs = linuxPkgs;
    inherit inputs;
  };
in
{
  packages = lib.recursiveUpdate (forEachSystem (
    { fleet, ... }:
    {
      inherit (fleet)
        fleet-agent
        fleet-server
        fleet-web
        fleetctl
        ;
    }
  )) { x86_64-linux.proxmox-template = proxmoxTemplate; };

  apps = forEachSystem (
    { pkgs, fleet }:
    {
      fleetctl = {
        type = "app";
        program = "${fleet.fleetctl}/bin/fleetctl";
        meta.description = "CLI for the fleet manager (status, force rebuild, promote)";
      };
      # `nix run .#fleet-demo`: the dashboard against a simulated fleet (needs git).
      fleet-demo = {
        type = "app";
        program = "${pkgs.writeShellScript "fleet-demo" ''
          export PATH=${pkgs.git}/bin:$PATH
          exec ${fleet.fleet-server}/bin/fleet-server demo "$@"
        ''}";
        meta.description = "fleet dashboard demo against a simulated fleet";
      };
    }
  );

  checks =
    lib.recursiveUpdate
      (forEachSystem (
        { fleet, ... }:
        {
          fleet-bindings = fleet.bindingsCheck;
        }
      ))
      {
        x86_64-linux.fleet-firewall = fleetFirewallCheck;
        x86_64-linux.fleet-vm = fleetVmTest;
      };

  devShells = forEachSystem (
    { pkgs, ... }:
    {
      fleet = pkgs.mkShell {
        packages = with pkgs; [
          cargo
          rustc
          clippy
          rustfmt
          nodejs_22
          sqlite
          git
        ];
      };
    }
  );
}
