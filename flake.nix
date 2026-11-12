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

    # Hermes Agent (Nous Research) and its NixOS module, on iris (modules/server/agent/).
    # Its own nixpkgs (nixos-unstable), not ours: its pinned pnpm/node don't build
    # against 26.05, and on its own pin they come from cache.nixos.org.
    hermes-agent.url = "github:NousResearch/hermes-agent";

    nixvim.url = "github:Waayway/nvim-config/nixvim";

    rofiThemeRepo = {
      url = "github:Murzchnvok/rofi-collection";
      flake = false;
    };

    # Server secrets from the 1Password vault Homelab (modules/server/secrets/opnix.nix).
    opnix = {
      url = "github:brizzbuzz/opnix";
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

    # TIDAL client mod (modules/workstation/apps/media.nix): the prebuilt release, the
    # same files on every platform. Bump the tag to update.
    tidaluna = {
      url = "https://github.com/Inrixia/TidaLuna/releases/download/1.17.1-beta/luna.zip";
      flake = false;
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Orakel Theater (modules/server/hosting/orakel.nix), imported by hestia only.
    # >>> SWITCH BEFORE MERGE: the branch is not on GitHub yet and the repo is private.
    # Until the owner pushes it (and grants the build hosts read access), evaluate with
    #   --override-input orakel "git+file:///var/lib/hermes/workspace/repos/orakel-nix2?submodules=1"
    # then set `ref` to the branch that was merged and run `nix flake lock --update-input orakel`.
    # No `inputs.nixpkgs.follows` (cut-over runbook F5): hestia then builds the same store
    # paths the orakel flake's own checks built and tested.
    orakel.url = "git+ssh://git@github.com/vanWaaijProductions/orakel-theater?ref=pr/orakel-arcanum-migration&submodules=1";
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
      inherit (programs) packages checks;
    };
}
