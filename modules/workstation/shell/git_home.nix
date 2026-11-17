{ lib, ... }:
{
  # Email is per host (work vs personal): set
  # `home-manager.users.<name>.programs.git.settings.user.email` in the host file.
  programs.git = {
    enable = true;
    settings = {
      user.name = "Thijs van Waaij";
      user.email = "43408024+Waayway@users.noreply.github.com";
      push.autoSetupRemote = true;
      pull.rebase = false;
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };
  # `gh auth login` rewrites config.yml, which fails on a read-only store
  # symlink. The generated file only holds gh defaults, so let gh own it.
  xdg.configFile."gh/config.yml".enable = lib.mkForce false;
}
