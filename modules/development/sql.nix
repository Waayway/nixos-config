{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    sql-studio
  ];
}
