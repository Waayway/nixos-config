{
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    Storage=persistent
  '';
}
