{ hostPlatform, ... }: {
  imports = [
    ./hardware.nix
    ./base
  ]
  ++ [ (if hostPlatform.isServer then ./servers else ./workstations) ];
}
