{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Read-only GitHub access for the servers, from the 1Password item `github-readonly`
# (Homelab vault, field `credential`: a fine-grained personal access token with
# Contents: read-only on the private repos we build from: vanWaaijProductions/orakel-theater
# and vanWaaijProductions/arcanum; expires after a year, renew it in the item).
#
# Why: every server builds its own system and evaluates the whole flake, so as soon as
# the flake has a private input (orakel) every server must be able to fetch private
# repos. Flake inputs are written as `git+ssh://git@github.com/<org>/<repo>`; here git
# rewrites that (and the private submodule's https URL) to https and answers the
# credential request from the opnix file. The token never enters the Nix store: the
# helper reads the file at fetch time. Workstations keep using their own ssh keys.
#
# Rollout order matters: a server can only fetch a private input once this has been
# applied to it, so this must reach every server BEFORE a commit that adds a private
# input is promoted to `stable`.
let
  cfg = config.secrets.githubReadonly;
  tokenFile = config.services.onepassword-secrets.secretPaths.githubReadonly;
  helper = pkgs.writeShellScript "github-readonly-credential" ''
    # git credential helper protocol: only answer "get", and only when the file exists.
    [ "$1" = get ] || exit 0
    [ -r ${tokenFile} ] || exit 0
    read -r token < ${tokenFile} || true
    [ -n "$token" ] || exit 0
    echo username=x-access-token
    echo "password=$token"
  '';
in
lib.optionalAttrs hostPlatform.isLinux {
  options.secrets.githubReadonly.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Give this server read-only access to the private GitHub repos (servers only).";
  };

  config = lib.mkIf (hostPlatform.isServer && cfg.enable) {
    services.onepassword-secrets.secrets.githubReadonly = {
      reference = "op://Homelab/github-readonly/credential";
      # root runs the Lodestar applies; wheel covers the admins who build by hand.
      owner = "root";
      group = "wheel";
      mode = "0440";
    };

    programs.git = {
      enable = true;
      config = {
        url."https://github.com/".insteadOf = [
          "ssh://git@github.com/"
          "git@github.com:"
        ];
        credential."https://github.com".helper = "${helper}";
      };
    };
  };
}
