# `homelab.people` and `homelab.access.<app>`: who exists and who may use which app.
# Plain data options (configure nothing), present on every host; `homelab.access` is
# collected flake-wide with `tools.accessFrom` and rendered into Kanidm and the router
# gate by later modules. People are declared once (modules/identity/people.nix).
{ lib, tools, ... }:
{
  options.homelab = {
    people = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            displayName = lib.mkOption {
              type = lib.types.str;
              description = "Full name shown in Kanidm and the apps.";
            };
            email = lib.mkOption {
              type = lib.types.str;
              description = "Email address of the person.";
            };
            admin = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether the person is an administrator.";
            };
          };
        }
      );
      default = { };
      description = "The people of the household, by login name.";
    };
    access = lib.mkOption {
      type = lib.types.attrsOf (tools.accessType { inherit lib; });
      default = { };
      description = "Who may use the apps on this configuration, by app name.";
    };
  };
}
