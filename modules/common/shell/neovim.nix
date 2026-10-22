{
  pkgs,
  inputs,
  ...
}:

{
  environment.systemPackages = [
    inputs.nixvim.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
