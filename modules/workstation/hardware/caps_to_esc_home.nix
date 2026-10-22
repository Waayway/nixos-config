{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isDarwin {
  # Karabiner-Elements equivalent of caps2esc -m 1 (caps_to_esc.nix).
  # The file is read-only (nix store), so changes made in the Karabiner GUI
  # won't stick; change them here instead.
  xdg.configFile."karabiner/karabiner.json".text = builtins.toJSON {
    profiles = [
      {
        name = "Default profile";
        selected = true;
        virtual_hid_keyboard.keyboard_type_v2 = "ansi";
        complex_modifications.rules = [
          {
            description = "Caps Lock: tap for Escape, hold for Control";
            manipulators = [
              {
                type = "basic";
                from = {
                  key_code = "caps_lock";
                  modifiers.optional = [ "any" ];
                };
                to = [
                  {
                    key_code = "left_control";
                    lazy = true;
                  }
                ];
                to_if_alone = [ { key_code = "escape"; } ];
              }
            ];
          }
        ];
      }
    ];
  };
}
