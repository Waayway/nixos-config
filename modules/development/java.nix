{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    jdk17
  ];
}
