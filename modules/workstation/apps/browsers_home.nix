{
  lib,
  osConfig ? null,
  hostPlatform,
  ...
}:
# Firefox as the default browser: what `xdg-open`, links clicked in other apps and the
# portals open. Written to ~/.config/mimeapps.list, which beats the system-wide default,
# so a browser that asks "make me the default?" cannot override it for good. Only when
# the firefox app is on (modules/workstation/apps/browsers.nix); the Hyprland Super+B bind
# (hyprland/config/lua/vars.lua) is separate and already starts it.
lib.optionalAttrs hostPlatform.isLinux {
  config =
    let
      browsers = osConfig.workstation.apps.browsers or null;
    in
    lib.mkIf (browsers != null && browsers.enable && browsers.firefox.enable) {
      xdg.mimeApps = {
        enable = true;
        defaultApplications = lib.genAttrs [
          "text/html"
          "application/xhtml+xml"
          "x-scheme-handler/http"
          "x-scheme-handler/https"
          "x-scheme-handler/about"
          "x-scheme-handler/unknown"
        ] (_: "firefox.desktop");
      };
    };
}
