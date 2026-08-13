{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    go_1_25
    gotools
    templ
    go-task
  ];
}
