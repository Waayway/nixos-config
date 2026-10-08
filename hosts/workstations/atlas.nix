# atlas — work MacBook Pro (M4 Max, macOS 27)
#
# Not installable declaratively — install by hand: Xcode, MacUtil.
{
  system = "aarch64-darwin";
  user = {
    name = "thijsvanwaaij";
    fullname = "Thijs van Waaij";
  };

  type = "macbook";

  options = {
    home-manager.enable = true;
    hardware.thermalforge.enable = true;

    workstation = {
      homebrew.removeUndeclared = "zap";

      apps = {
        browsers.enable = true;
        communication = {
          enable = true;
          element.enable = false;
        };
        media.enable = true;
        office.enable = true;
        ai = {
          enable = true;
          codex.enable = false;
        };
        editors.enable = true;
        database = {
          enable = true;
          sqlitebrowser.enable = false;
        };
        utilities.enable = true;
      };
    };
  };

  config =
    { ... }:
    {
      home-manager.users.thijsvanwaaij = {
        programs.git.settings.user.email = "thijs@vriend.studio";

        # Finder sidebar Favorites. Folders that don't exist yet (Drive not
        # synced, repos not cloned) are added on a later switch.
        darwin.finderSidebar = [
          "My Drive/Cuneus"
          "oteny"
          "oteny/rivermen"
          "Desktop"
          "Documents"
          "Downloads"
          "Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
        ];
      };
    };
}
