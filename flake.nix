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
      # Upstream pins brew 5.1.1, which has a regression where
      # `cask_struct_generator.rb` crashes with "undefined method 'to_sym'
      # for nil" while parsing depends_on from the cask API. 5.1.14 fixes it.
      inputs.brew-src = {
        url = "github:Homebrew/brew/5.1.14";
        flake = false;
      };
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    nixvim.url = "github:Waayway/nvim-config/nixvim";

    fw-fanctrl = {
      url = "github:TamtamHero/fw-fanctrl/packaging/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

      isDarwinHost = h: nixpkgs.lib.hasSuffix "darwin" h.system;

      nixosHosts  = nixpkgs.lib.filterAttrs (_: h: !(isDarwinHost h)) hosts;
      darwinHosts = nixpkgs.lib.filterAttrs (_: h:  (isDarwinHost h)) hosts;
      deployHosts = nixpkgs.lib.filterAttrs (_: h:  h ? deploy)       hosts;

      nixosConfigurations  = nixpkgs.lib.mapAttrs mkSystem nixosHosts;
      darwinConfigurations = nixpkgs.lib.mapAttrs mkDarwin darwinHosts;

      deployNodes = nixpkgs.lib.mapAttrs
        (name: h: mkDeployNode name h nixosConfigurations.${name})
        deployHosts;
    in
    {
      inherit nixosConfigurations darwinConfigurations;
      deploy.nodes = deployNodes;

      packages.x86_64-linux.proxmox-template = inputs.nixos-generators.nixosGenerate {
        system  = "x86_64-linux";
        format  = "proxmox";
        modules = [ ./template/proxmox.nix ];
      };
    };
}
