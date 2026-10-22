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
            icon = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              example = lib.literalExpression "../identity/branding/icons/nextcloud.svg";
              description = ''
                The app's icon in Kanidm's app list (SVG, PNG, JPEG, GIF or WebP, at most
                256 KiB and 1024×1024; modules/identity/branding/icons has some),
                uploaded on every provisioning run. null leaves the image in Kanidm as it
                is (Kanidm's default icon for a new client; a removed icon stays until
                deleted there).
              '';
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
            preferShortUsername = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Send the short name (`thijs`) as `preferred_username` instead of Kanidm's
                spn (`thijs@id.vanwaaij.com`).
              '';
            };
            usernames = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              example = {
                thijs = "Waayway";
              };
              description = ''
                Members' user names in the app where they differ from their Kanidm name
                (accounts that predate Kanidm). Non-empty: every member's name in the app
                (this value, else the Kanidm name) is sent in the claim `<app>_username`,
                which the app maps to its user ID. Kanidm sets claims by group, so each
                member gets a one-person group `<app>-username-<member>`.
              '';
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
