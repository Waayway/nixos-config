{ user, ... }:
{
  # macOS manages the actual user account; nix-darwin just needs to know
  # where the home directory is so home-manager can target it. Avoid
  # setting `shell`/`description` here — that fights with existing dscl
  # state on a pre-existing account.
  users.users.${user.name} = {
    home = "/Users/${user.name}";
  };
}
