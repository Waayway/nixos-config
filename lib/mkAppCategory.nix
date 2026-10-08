# Builds a `workstation.apps.<name>` module from a list of apps.
#
# Every app gets `workstation.apps.<name>.<app>.enable` (default: true), so a
# host enables the whole category and can switch single apps off:
#
#   workstation.apps.media = {
#     enable = true;
#     krita.enable = false;
#   };
#
# Per app, each field is optional:
#   linux        list of packages installed on NixOS
#   linuxConfig  NixOS config applied when the app is enabled (e.g. programs.*)
#   darwinPkgs   list of packages installed on nix-darwin
#   darwinCasks  list of Homebrew casks installed on nix-darwin
# An app without a field for the current platform is simply not installed there.
#
# Usage in a module:
#   args@{ ... }: import ../../lib/mkAppCategory.nix args { name = "..."; apps = { ... }; }
{
  config,
  lib,
  hostPlatform,
  ...
}:
{ name, apps }:
let
  cfg = config.workstation.apps.${name};
  isOn = app: cfg.enable && cfg.${app}.enable;
  collect =
    field:
    lib.concatLists (lib.mapAttrsToList (app: a: lib.optionals (isOn app) (a.${field} or [ ])) apps);
in
{
  options.workstation.apps.${name} = {
    enable = lib.mkEnableOption "the ${name} apps";
  }
  // lib.mapAttrs (app: _: {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install ${app} when workstation.apps.${name} is enabled.";
    };
  }) apps;

  config = lib.mkMerge (
    [
      (lib.optionalAttrs hostPlatform.isLinux {
        environment.systemPackages = collect "linux";
      })
      (lib.optionalAttrs hostPlatform.isDarwin {
        environment.systemPackages = collect "darwinPkgs";
        homebrew.casks = collect "darwinCasks";
      })
    ]
    ++ lib.optionals hostPlatform.isLinux (
      lib.mapAttrsToList (app: a: lib.mkIf (isOn app) a.linuxConfig) (
        lib.filterAttrs (_: a: a ? linuxConfig) apps
      )
    )
  );
}
