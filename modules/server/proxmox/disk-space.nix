# The VMs' root disks are small (16 GB on router, identity, monitor) and the weekly GC
# (common/nix/nix.nix) can be too late: one failed build fills them (2026-10-29). Nix
# collects garbage itself when free space drops below `min-free`, during builds and
# applies, until `max-free` is free again. Only dead paths go; generations stay.
{
  lib,
  hostPlatform,
  serverOptions ? { },
  ...
}:
let
  enabled =
    hostPlatform.isLinux && hostPlatform.isServer && (serverOptions.useDefaultHardware or null) == true;
  gib = 1024 * 1024 * 1024;
in
lib.optionalAttrs enabled {
  nix.settings = {
    min-free = 1 * gib;
    max-free = 4 * gib;
  };
}
