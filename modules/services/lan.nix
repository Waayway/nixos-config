{
  lib,
  serverOptions ? { },
  ...
}:
# Where a homelab VM's services listen on the LAN: the NIC (virtio-net on the Proxmox
# template comes up as ens18) and the host file's `netInterface.ip`. The service
# modules open their ports on this interface only and give the router this address
# as their backend.
{
  options.homelab.lan = {
    interface = lib.mkOption {
      type = lib.types.str;
      default = "ens18";
      description = "The VM's LAN interface; service ports are opened on it only.";
    };
    address = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = (serverOptions.netInterface or { }).ip or null;
      defaultText = lib.literalExpression "serverOptions.netInterface.ip or null";
      description = "The VM's LAN address, used as the backend of its routes.";
    };
  };
}
