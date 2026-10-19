# The type of one app's access: `homelab.access.<app>` and the elements of
# `homelab.identity.extraAccess`. Used as `tools.accessType { inherit lib; }`.
{ lib }:
lib.types.submodule {
  options = {
    members = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "thijs" ];
      description = "Names from `homelab.people` who may use the app.";
    };
    oidc = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            originUrls = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Allowed redirect (callback) URLs of the OAuth2 client.";
            };
            originLanding = lib.mkOption {
              type = lib.types.str;
              description = "The app's landing URL, shown in Kanidm's app list.";
            };
            scopes = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "openid"
                "email"
                "profile"
                "groups"
              ];
              description = "Scopes granted to members.";
            };
          };
        }
      );
      default = null;
      description = "OAuth2 client settings; null means the app has no OIDC login.";
    };
    gate = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether the router puts the sign-in gate in front of the app.";
    };
  };
}
