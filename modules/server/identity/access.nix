{
  config,
  lib,
  hostPlatform,
  ...
}:
# Access to the apps this flake doesn't run (`homelab.identity.extraAccess`): the
# ones behind the router's sign-in gate (Archipelago, the Traefik dashboard, TrueNAS,
# Backrest; their routes are in modules/server/homelab/routes.nix) and Proxmox VE, which
# signs in through its own OpenID realm (`pveum realm add kanidm …`; Proxmox sends its
# UI's origin as redirect URL, so both addresses it's opened on are listed).
# These are Thijs's only; Arie has Nextcloud, Immich and Jellyfin (their modules).
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf config.homelab.identity.enable {
    homelab.identity.extraAccess =
      lib.genAttrs
        [
          "archipelago"
          "traefik"
          "truenas"
          "backrest"
        ]
        (_: {
          members = [ "thijs" ];
          gate = true;
        })
      // {
        proxmox = {
          members = [ "thijs" ];
          oidc = {
            originUrls = [
              "https://pve.tail41ca60.ts.net:8006"
              "https://10.0.10.50:8006"
            ];
            originLanding = "https://pve.tail41ca60.ts.net:8006";
            icon = ./branding/icons/proxmox.svg;
            # Proxmox user names are `<name>@kanidm`; the long form would add a second `@`.
            preferShortUsername = true;
          };
        };
      };
  };
}
