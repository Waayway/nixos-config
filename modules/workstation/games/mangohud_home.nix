{
  config,
  lib,
  osConfig ? null,
  hostPlatform,
  ...
}:
# MangoHud's config, ~/.config/MangoHud/: MangoHud.conf (preset order, keybinds, log folder)
# and presets.conf (the layouts), kept as plain files in mangohud/ next to this one. Both
# `mangohud %command%` and gamescope's `--mangoapp` (ScopeBuddy, scopebuddy_home.nix) read
# them. Linked out of the store into ~/.flake like the Hyprland config: edit the files and
# the HUD picks them up (Shift_L+F4 reloads), no switch needed. An existing file there
# (goverlay writes them) is moved aside as *.before-nix on the first switch.
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (osConfig != null && (osConfig.programs.games.enable or false)) (
    let
      files = "${config.home.homeDirectory}/.flake/modules/workstation/games/mangohud";
    in
    {
      xdg.configFile."MangoHud/MangoHud.conf".source =
        config.lib.file.mkOutOfStoreSymlink "${files}/MangoHud.conf";
      xdg.configFile."MangoHud/presets.conf".source =
        config.lib.file.mkOutOfStoreSymlink "${files}/presets.conf";

      # output_folder in MangoHud.conf: Shift_L+F2 logs there.
      home.activation.mangologs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "${config.home.homeDirectory}/mangologs"
      '';
    }
  );
}
