{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    nodejs_22
    deno
    bun
  ];
}
