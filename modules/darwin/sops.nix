{ user, ... }:
{
  sops.defaultSopsFile = ../../../secrets/workstations/apollo.yaml;

  # Darwin doesn't have /etc/ssh/ssh_host_ed25519_key by default — fall back to
  # the user's personal age key in ~/.config/sops/age/keys.txt (same identity
  # as the `thijs_macbook` recipient in .sops.yaml). Derive a host_apollo
  # recipient and add to .sops.yaml once we want apollo's system keychain to
  # decrypt without the user key.
  sops.age.keyFile = "/Users/${user.name}/.config/sops/age/keys.txt";
}
