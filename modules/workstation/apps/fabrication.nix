args@{
  config,
  lib,
  tools,
  ...
}:
let
  # Set where Hyprland stops scaling XWayland windows (games/steam-scaling.nix).
  steamScale = config.programs.games.steamScale or null;
  xwaylandUnscaled = (config.programs.games.enable or false) && steamScale != null;
in
tools.mkAppCategory args {
  name = "fabrication";
  apps = {
    # Slicer for the Bambu Lab printer. Flathub's build is Bambu Lab's own and
    # ships the network plugin (cloud/LAN printing); nixpkgs' lags behind.
    bambu-studio = {
      flatpak = [ "com.bambulab.BambuStudio" ];
      darwinCasks = [ "bambu-studio" ];
      # Bambu Studio always runs through XWayland (it sets GDK_BACKEND=x11 itself).
      # Where XWayland windows are drawn at 1x, GTK has to scale the interface:
      # GDK_SCALE, whole numbers only, so the Steam scale rounded (1.6 -> 2).
      # Elsewhere Hyprland already scales it and GDK_SCALE would double it.
      linuxConfig = lib.mkIf xwaylandUnscaled {
        services.flatpak.overrides."com.bambulab.BambuStudio".Environment.GDK_SCALE = toString (
          builtins.floor (steamScale + 0.5)
        );
      };
    };
  };
}
