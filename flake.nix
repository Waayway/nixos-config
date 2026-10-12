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

    lodestar = {
      url = "github:Waayway/lodestar";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Machines live in systems.nix, our own programs (packages) in programs.nix.
  outputs =
    inputs:
    let
      systems = import ./systems.nix { inherit inputs; };
      programs = import ./programs.nix { inherit inputs; };
    in
    {
      inherit (systems)
        nixosConfigurations
        darwinConfigurations
        deploy
        ;
      inherit (programs) packages;
    };
}
