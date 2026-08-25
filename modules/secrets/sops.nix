{
  lib,
  hostPlatform,
  currentSystemName,
  user,
  ...
}:
{
  sops.defaultSopsFile =
    if (builtins.pathExists ../../../secrets/${currentSystemName}.yaml) then
      ../../secrets/${currentSystemName}.yaml
    else
      ../../secrets/common.yaml;

  # Derive the age private key from the host's SSH host key — no separate
  # age key material on the host. The SSH host key has to exist for SSH
  # to work, so we reuse it. Onboarding a new host: harvest its host
  # pubkey via `ssh-keyscan`, convert with `ssh-to-age`, add to .sops.yaml,
  # then `sops updatekeys secrets/*.yaml` to re-encrypt.
  #
  # Per-host overrides (e.g. apollo using a user keyFile) live in their own
  # platform module and just set `sops.age.keyFile` alongside.
  sops.age.sshKeyPaths = lib.mkDefault [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.age.keyFile =
    "${if hostPlatform.isDarwin then "/Users/${user.name}" else "/home/${user.name}"}/.config/sops/age/keys.txt";
}
