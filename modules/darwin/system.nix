{
  pkgs,
  currentSystemName,
  hostPlatform,
  user,
  lib,
  ...
}:
{
  config = lib.optionalAttrs hostPlatform.isDarwin {
    networking.hostName = currentSystemName;
    networking.computerName = currentSystemName;

    programs.zsh.enable = true;
    environment.shells = with pkgs; [ zsh ];

    environment.variables.EDITOR = "nvim";

    # Touch-ID for sudo
    security.pam.services.sudo_local.touchIdAuth = true;

    networking.applicationFirewall.enable = true;

    # Display sleeps after an hour (battery and AC).
    power.sleep.display = 60;

    # Most `defaults` (scroll direction, keyboard, ...) are only read at login;
    # make the running session pick them up right after activation.
    system.activationScripts.postActivation.text = ''
      # Handoff off: no "Open on <other device>" in Cmd-Tab / Dock. These keys
      # are per-machine (-currentHost), which system.defaults can't write.
      for key in ActivityAdvertisingAllowed ActivityReceivingAllowed; do
        launchctl asuser "$(id -u -- ${user.name})" sudo --user=${user.name} -- \
          defaults -currentHost write com.apple.coreservices.useractivityd "$key" -bool false
      done

      launchctl asuser "$(id -u -- ${user.name})" sudo --user=${user.name} -- \
        /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u || true
    '';
  };
}
