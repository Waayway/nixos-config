args@{ tools, ... }:
tools.mkAppCategory args {
  name = "fabrication";
  apps = {
    # Slicer for the Bambu Lab printer. Flathub's build is Bambu Lab's own and
    # ships the network plugin (cloud/LAN printing); nixpkgs' lags behind.
    bambu-studio = {
      flatpak = [ "com.bambulab.BambuStudio" ];
      darwinCasks = [ "bambu-studio" ];
    };
  };
}
