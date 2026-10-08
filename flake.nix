{
  description = "Nixos configuration **Waayway**";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
      # Pin brew ourselves: 7.0.8 is the first release here that knows
      # macOS 27 (golden_gate), needed for atlas. (Older brew can also crash
      # parsing the current cask API.)
      inputs.brew-src = {
        url = "github:Homebrew/brew/7.0.8";
        flake = false;
      };
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    nixvim.url = "github:Waayway/nvim-config/nixvim";

    rofiThemeRepo = {
      url = "github:Murzchnvok/rofi-collection";
      flake = false;
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      version = "26.05";

      overlays = [ ];

      isDarwinHost = h: nixpkgs.lib.hasSuffix "darwin" h.system;

      mkSystem = import ./lib/mkSystem.nix {
        inherit
          overlays
          nixpkgs
          inputs
          version
          ;
      };

      mkDarwin = import ./lib/mkDarwin.nix {
        inherit
          overlays
          nixpkgs
          inputs
          version
          ;
      };

      mkDeployNode = import ./lib/mkDeployNode.nix { inherit inputs; };

      hosts = (import ./lib/discoverHosts.nix { lib = nixpkgs.lib; }) ./hosts;

      nixosHosts = nixpkgs.lib.filterAttrs (_: h: !(isDarwinHost h)) hosts;
      darwinHosts = nixpkgs.lib.filterAttrs (_: h: (isDarwinHost h)) hosts;
      deployHosts = nixpkgs.lib.filterAttrs (_: h: h ? deploy) hosts;

      nixosConfigurations = nixpkgs.lib.mapAttrs mkSystem nixosHosts;
      darwinConfigurations = nixpkgs.lib.mapAttrs mkDarwin darwinHosts;

      deployNodes = nixpkgs.lib.mapAttrs (
        name: h: mkDeployNode name h nixosConfigurations.${name}
      ) deployHosts;
    in
    {
      inherit nixosConfigurations darwinConfigurations;
      deploy.nodes = deployNodes;

      packages.x86_64-linux.proxmox-template = inputs.nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "proxmox";
        modules = [ ./template/proxmox.nix ];
      };
    };
}
