{ pkgs, currentUser, ... }:
let
  tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
  session = "${pkgs.hyprland}/bin/start-hyprland";
in
{
  # Enable Display Manager
  services.greetd = {
    enable = true;
    restart = false;

    settings = {
      initial_session = {
        command = "${session}";
        user = "${currentUser.name}";
      };
      default_session = {
        command = "${tuigreet} --greeting 'Welcome to NixOS!' --asterisks --remember --remember-user-session --time --cmd ${session}";
        user = "greeter";
      };
    };
  };
}
