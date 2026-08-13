{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    rustup
  ];
}
