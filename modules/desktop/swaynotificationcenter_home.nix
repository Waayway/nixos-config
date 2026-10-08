{ pkgs, lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux ({
  services.swaync = {
    enable = true;
    style =
      "\n@define-color cc-bg rgba(26, 27, 38, 1);\n@define-color noti-border-color rgba(255, 255, 255, 0.15);\n@define-color noti-bg rgb(17, 17, 27);\n@define-color noti-bg-darker rgb(43, 43, 57);\n@define-color noti-bg-hover rgb(27, 27, 43);\n@define-color noti-bg-focus rgba(27, 27, 27, 0.6);\n@define-color noti-close-bg rgba(255, 255, 255, 0.1);\n@define-color noti-close-bg-hover rgba(255, 255, 255, 0.15);\n@define-color text-color rgba(169, 177, 214, 1);\n@define-color text-color-disabled rgb(150, 150, 150);\n@define-color bg-selected rgb(0, 128, 255);\n\n* {\n  font-family: JetBrainsMono NFM SemiBold;\n}\n\n.control-center .notification-row:focus,\n.control-center .notification-row:hover {\n  opacity: 1;\n  background: @noti-bg-darker;\n}\n\n.notification-row {\n  outline: none;\n  margin: 0px;\n  padding: 0px;\n}\n\n.notification {\n  background: @cc-bg;\n  border: 2px solid #34548a;\n  border-radius: 0px;\n  margin: 3px -2px 3px 0px;\n}\n\n.notification-content {\n  background: @cc-bg;\n}\n\n.notification-default-action {\n  margin: 0;\n  padding: 0;\n  border-radius: 0px;\n}\n\n.close-button {\n  background: #f7768e;\n  color: @cc-bg;\n  text-shadow: none;\n  padding: 0px;\n  border-radius: 0px;\n  margin-top: 5px;\n  margin-right: 5px;\n}\n\n.close-button:hover {\n  box-shadow: none;\n  background: #f7768e;\n  transition: all 0.15s ease-in-out;\n  border: none;\n}\n\n.notification-action {\n  border: 2px solid #34548a;\n  border-top: none;\n  border-radius: 0px;\n}\n\n.notification-default-action:hover,\n.notification-action:hover {\n  color: #7aa2f7;\n  background: @cc-bg;\n}\n\n.notification-default-action {\n  border-radius: 5px;\n  margin: 0px;\n}\n\n.notification-default-action:not(:only-child) {\n  border-bottom-left-radius: 7px;\n  border-bottom-right-radius: 7px;\n}\n\n.notification-action:first-child {\n  border-bottom-left-radius: 10px;\n  background: #1b1b2b;\n}\n\n.notification-action:last-child {\n  border-bottom-right-radius: 10px;\n  background: #1b1b2b;\n}\n\n.inline-reply {\n  margin-top: 8px;\n}\n\n.inline-reply-entry {\n  background: @noti-bg-darker;\n  color: @text-color;\n  caret-color: @text-color;\n  border: 1px solid @noti-border-color;\n  border-radius: 5px;\n}\n\n.inline-reply-button {\n  margin-left: 4px;\n  background: @noti-bg;\n  border: 1px solid @noti-border-color;\n  border-radius: 5px;\n  color: @text-color;\n}\n\n.inline-reply-button:disabled {\n  background: initial;\n  color: @text-color-disabled;\n  border: 1px solid transparent;\n}\n\n.inline-reply-button:hover {\n  background: @noti-bg-hover;\n}\n\n.image {\n  border-radius: 0px;\n  margin-right: 10px;\n}\n\n.summary {\n  font-size: 16px;\n  font-weight: 700;\n  background: transparent;\n  color: rgba(158, 206, 106, 1);\n  text-shadow: none;\n}\n\n.time {\n  font-size: 16px;\n  font-weight: 700;\n  background: transparent;\n  color: @text-color;\n  text-shadow: none;\n  margin-right: 18px;\n}\n\n.body {\n  font-size: 15px;\n  font-weight: 400;\n  background: transparent;\n  color: @text-color;\n  text-shadow: none;\n}\n\n.control-center {\n  background: @cc-bg;\n  border: 2px solid #34548a;\n  border-radius: 0px;\n}\n\n.control-center-list {\n  background: transparent;\n}\n\n.control-center-list-placeholder {\n  opacity: 0.5;\n}\n\n.floating-notifications {\n  background: transparent;\n}\n\n.blank-window {\n  background: alpha(black, 0.1);\n}\n\n.widget-title {\n  color: #7aa2f7;\n  background: @noti-bg-darker;\n  padding: 5px 10px;\n  margin: 10px 10px 5px 10px;\n  font-size: 1.5rem;\n  border-radius: 5px;\n}\n\n.widget-title>button {\n  font-size: 1rem;\n  color: @text-color;\n  text-shadow: none;\n  background: @noti-bg;\n  box-shadow: none;\n  border-radius: 5px;\n}\n\n.widget-title>button:hover {\n  background: #f7768e;\n  color: @cc-bg;\n}\n\n.widget-dnd {\n  background: @noti-bg-darker;\n  padding: 5px 10px;\n  margin: 5px 10px;\n  border-radius: 5px;\n  font-size: large;\n  color: #7aa2f7;\n}\n\n.widget-dnd>switch {\n  border-radius: 5px;\n  background: #7aa2f7;\n}\n\n.widget-dnd>switch:checked {\n  background: #f7768e;\n  border: 1px solid #f7768e;\n}\n\n.widget-dnd>switch slider,\n.widget-dnd>switch:checked slider {\n  background: @cc-bg;\n  border-radius: 5px;\n}\n\n.widget-label {\n  margin: 10px 10px 5px 10px;\n}\n\n.widget-label>label {\n  font-size: 1rem;\n  color: @text-color;\n}\n\n.widget-mpris {\n  color: @text-color;\n  background: @noti-bg-darker;\n  padding: 5px 10px;\n  margin: 5px 10px 5px 10px;\n  border-radius: 0px;\n  box-shadow: none;\n}\n\n.widget-mpris>box>button {\n  border-radius: 5px;\n}\n\n.widget-mpris-player {\n  padding: 5px 10px;\n  margin: 10px;\n  border-radius: 0px;\n  box-shadow: none;\n}\n\n.widget-mpris-title {\n  font-weight: 700;\n  font-size: 1.25rem;\n}\n\n.widget-mpris-subtitle {\n  font-size: 1.1rem;\n}\n\n.widget-mpris-album-art {\n  border-radius: 0px;\n}\n\n.widget-buttons-grid {\n  font-size: x-large;\n  padding: 5px;\n  margin: 10px 10px 5px 10px;\n  border-radius: 0px;\n  background: @noti-bg-darker;\n}\n\n.widget-buttons-grid>flowbox>flowboxchild>button {\n  margin: 3px;\n  background: @cc-bg;\n  border-radius: 0px;\n  color: @text-color;\n}\n\n.widget-buttons-grid>flowbox>flowboxchild>button:hover {\n  background: rgba(122, 162, 247, 1);\n  color: @cc-bg;\n}\n\n.widget-buttons-grid>flowbox>flowboxchild>button:checked {\n  background: rgb(158, 206, 106);\n  color: @cc-bg;\n}\n\n.widget-menubar>box>.menu-button-bar>button {\n  border: none;\n  background: transparent;\n}\n\n.topbar-buttons>button {\n  border: none;\n  background: transparent;\n}\n\n.widget-volume {\n  background: @noti-bg-darker;\n  padding: 5px;\n  margin: 5px 10px;\n  border-radius: 0px;\n  font-size: 2rem;\n  color: #7aa2f7;\n}\n\n.widget-backlight {\n  background: @noti-bg-darker;\n  padding: 5px;\n  margin: 5px 10px;\n  border-radius: 0px;\n  font-size: 2rem;\n  color: #7aa2f7;\n}\n      ";
    settings = {
      positionX = "right";
      positionY = "top";
      control-center-margin-top = 10;
      control-center-margin-bottom = 10;
      control-center-margin-right = 10;
      notification-icon-size = 64;
      notification-body-image-height = 100;
      notification-body-image-width = 200;
      timeout = 10;
      timeout-low = 5;
      timeout-critical = 0;
      fit-to-screen = false;
      control-center-width = 500;
      control-center-height = 1033;
      notification-window-width = 500;
      keyboard-shortcuts = true;
      image-visibility = "when-available";
      transition-time = 200;
      hide-on-clear = false;
      hide-on-action = true;
      script-fail-notify = true;
      widgets = [ "buttons-grid" "volume" "backlight" "mpris" ];
      widget-config = {
        title = {
          text = "Notification Center";
          clear-all-button = true;
          button-text = "󰆴 Clear";
        };
        dnd = { text = "Do Not Disturb"; };
        label = {
          max-lines = 1;
          text = "Notification Center";
        };
        mpris = {
          image-size = 100;
          image-radius = 0;
          blacklist = [ "kew" "firefox" ];
        };
        volume = { label = "󰕾"; };
        backlight = { label = "󰃟"; };
        buttons-grid = {
          actions = [
            {
              label = "󰆴";
              command = "swaync-client -C";
            }
            {
              label = "󰕾";
              command = "pactl set-sink-mute @DEFAULT_SINK@ toggle";
              type = "toggle";
            }
            {
              label = "󰍬";
              command = "pactl set-source-mute @DEFAULT_SOURCE@ toggle";
              type = "toggle";
            }
            {
              label = "󰂯";
              command = "blueberry";
            }
          ];
        };
      };
    };
  };
})
