{ ... }:
{
  # Email is per host (work vs personal): set
  # `home-manager.users.<name>.programs.git.settings.user.email` in the host file.
  programs.git = {
    enable = true;
    settings = {
      user.name = "Thijs van Waaij";
      push.autoSetupRemote = true;
      pull.rebase = false;
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };
}
