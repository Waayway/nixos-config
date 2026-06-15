# Builds a deploy-rs node entry from a host's nixosConfiguration + its
# `deploy = { ip, sshKey?, ... }` attrs. Called from flake.nix for any host
# that declares a `deploy` attr.
{ inputs }:

name: hostAttrs: nixosConfig:

let
  deploy = hostAttrs.deploy;
  system = hostAttrs.system;
in
{
  hostname = deploy.ip;
  sshUser  = hostAttrs.user.name;
  sshOpts  = [ "-i" deploy.sshKey ];
  profiles.system = {
    user          = "root";
    path          = inputs.deploy-rs.lib.${system}.activate.nixos nixosConfig;
    autoRollback  = true;
    magicRollback = true;
  };
}
