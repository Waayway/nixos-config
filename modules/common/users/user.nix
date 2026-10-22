{
  user,
  hostPlatform,
  lib,
  ...
}:
{
  config = lib.mkMerge [
    {
      users.users.${user.name} = {
        description = user.fullname;
        home = (if hostPlatform.isLinux then "/home/${user.name}" else "/Users/${user.name}");
      };
    }
    # nix-darwin can't manage groups/passwords of the (pre-existing) macOS user,
    # and has no sudo/root password options — keep those Linux-only.
    (lib.optionalAttrs hostPlatform.isLinux {
      security.sudo.wheelNeedsPassword = false;

      users.users.${user.name} = {
        isNormalUser = true;
        extraGroups = [
          "users"
          "networkmanager"
          "wheel"
          "audio"
          "video"
        ];
      };
      # Root: password disabled, key-only via the break-glass key
      # (modules/server/users/user.nix).
      users.users.root.hashedPassword = "!";
    })
  ];
}
