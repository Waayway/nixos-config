{ pkgs, ... }:
{
  # Nix-installed GUI apps for darwin go here. They will be copied into
  # /Applications/Nix Apps/ by modules/darwin/applications.nix.
  #
  # Currently empty: discord comes in through
  # modules/workstations/applications/communication.nix, and ghostty is
  # managed by the home-manager module in
  # modules/workstations/terminal/ghostty_home.nix.
  #
  # Add nixpkgs-sourced GUI apps here as you verify they build on
  # aarch64-darwin (e.g. pkgs.spotify, pkgs.obsidian). Anything that fails
  # to build should move to modules/darwin/homebrew.nix casks instead.
  environment.systemPackages = [
    pkgs.obsidian
  ];
}
