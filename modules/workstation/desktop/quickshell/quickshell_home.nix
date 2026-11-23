{
  config,
  pkgs,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux (
  let
    # The screen-share picker for xdg-desktop-portal-hyprland (custom_picker_binary in
    # hyprland/config/xdph.conf). The portal runs it and reads one line from stdout,
    # "[SELECTION]<flags>/<screen:NAME|window:ID>"; nothing means cancelled. The UI is the
    # running Quickshell (config/share/SharePicker.qml), opened over IPC; the choice comes
    # back through a file. Without a running Quickshell it falls back to the stock Qt picker.
    sharePicker = pkgs.writeShellApplication {
      name = "quickshell-share-picker";
      runtimeInputs = [
        pkgs.quickshell
        pkgs.coreutils
      ];
      text = ''
        allow=false
        for arg in "$@"; do
          [ "$arg" = --allow-token ] && allow=true
        done

        out="''${XDG_RUNTIME_DIR:-/tmp}/quickshell-share-picker.$$"
        rm -f "$out"
        if ! qs ipc call sharepicker open "''${XDPH_WINDOW_SHARING_LIST:-}" "$allow" "$out" >/dev/null 2>&1; then
          exec hyprland-share-picker "$@"
        fi

        # Two minutes to choose, then it counts as cancelled.
        for _ in $(seq 1200); do
          if [ -e "$out" ]; then
            selection="$(cat "$out")"
            rm -f "$out"
            [ -n "$selection" ] && printf '[SELECTION]%s\n' "$selection"
            exit 0
          fi
          sleep 0.1
        done
        qs ipc call sharepicker close >/dev/null 2>&1 || true
        exit 1
      '';
    };
  in
  {
    # Bar and notifications (replaces eww and swaync). Started by Hyprland
    # (hyprland/config/lua/autostart.lua). ~/.config/quickshell is the repo
    # folder itself, so edits apply live (Quickshell reloads on save).
    home.packages = [
      pkgs.quickshell
      sharePicker
    ];

    xdg.configFile."quickshell".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.flake/modules/workstation/desktop/quickshell/config";
  }
)
