{
  user,
  hostPlatform,
  ...
}:
{
  users.users.${user.name} = {
    description = user.fullname;
    home = (if hostPlatform.isLinux then "/home/${user.name}" else "/Users/${user.name}");
    isNormalUser = true;
    extraGroups = [
      "users"
      "networkmanager"
      "wheel"
      "audio"
      "video"
    ];
  };
}
