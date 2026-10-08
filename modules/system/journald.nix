{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux ({
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    Storage=persistent
  '';
})
