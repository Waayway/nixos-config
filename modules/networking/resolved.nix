{
  # Without a DHCP client or NetworkManager, `networking.nameservers` alone
  # doesn't actually land in /etc/resolv.conf (resolvconf has no service to
  # push the entries). systemd-resolved fixes that — it reads
  # `networking.nameservers` and serves DNS via a stub resolver on
  # 127.0.0.53, which both the host and docker containers can use.
  services.resolved.enable = true;
}
