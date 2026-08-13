{ config, pkgs, lib, ... }:
{
  # nixpkgs GUI apps land in /nix/store/.../Applications and are invisible
  # to Spotlight and Launchpad. Copy them into /Applications/Nix Apps/ on
  # each activation so macOS can index them.
  #
  # Canonical community snippet — rsyncs the .app bundles out of the store
  # instead of symlinking (macOS signature checks don't follow symlinks).
  system.activationScripts.applications.text = lib.mkForce ''
    echo "setting up /Applications/Nix Apps..." >&2
    rm -rf "/Applications/Nix Apps"
    mkdir -p "/Applications/Nix Apps"
    find ${config.system.build.applications}/Applications -maxdepth 1 -type l -print0 | \
      while IFS= read -r -d "" link; do
        src=$(/usr/bin/stat -f%Y "$link")
        app_name=$(basename "$link")
        ${pkgs.rsync}/bin/rsync --archive --delete "$src/" "/Applications/Nix Apps/$app_name"
      done
  '';
}
