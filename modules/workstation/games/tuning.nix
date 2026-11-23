{
  config,
  lib,
  pkgs,
  hostPlatform,
  user,
  ...
}:
# The CachyOS-style part of `programs.games.enable`: what makes a gaming desktop feel
# tight on CachyOS, as far as it can be had on NixOS without a custom kernel:
#   - a sched_ext scheduler (scx_lavd, latency-aware, made for desktops and games) where
#     CachyOS ships BORE; needs the mainline kernel from modules/common/boot/kernel.nix
#   - ananicy-cpp with the CachyOS rule set (it gives games and the desktop their nice
#     levels, I/O classes and scheduling policies)
#   - zram swap with zstd, and the vm.* settings that go with it
#   - the sysctls Proton and Wine expect (vm.max_map_count) and the split-lock one
#   - gamemode, so `gamemoderun %command%` renices a game
#   - ntsync, the kernel's NT sync primitives, which current Proton uses when it finds them
# Not here: a kernel built for x86-64-v3 or with BORE (docs/gaming.md, "Going further").
# Everything below is plain NixOS and reversible: switch `programs.games.tuning.enable`
# off, or null the scheduler, and the next switch undoes it.
let
  cfg = config.programs.games;
in
lib.optionalAttrs hostPlatform.isLinux {
  options.programs.games.tuning = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Apply the CachyOS-style tuning below when programs.games.enable is on.";
    };
    scheduler = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "scx_lavd";
      example = "scx_bpfland";
      description = ''
        The sched_ext scheduler (services.scx.scheduler). null keeps the kernel's default
        scheduler (EEVDF). scx_lavd and scx_bpfland are the two to try for desktop and games.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.tuning.enable && !hostPlatform.isServer) {
    services.scx = lib.mkIf (cfg.tuning.scheduler != null) {
      enable = true;
      scheduler = cfg.tuning.scheduler;
      package = pkgs.scx.rustscheds;
    };

    services.ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };

    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;
    };

    boot.kernel.sysctl = {
      # Proton and Wine games map a lot of memory; Valve's value, NixOS defaults to 1048576
      # which some games (Hogwarts Legacy, DayZ, Star Citizen) exceed.
      "vm.max_map_count" = lib.mkForce 2147483642;
      # Split-lock detection makes some games stutter (a trap per split lock access).
      "kernel.split_lock_mitigate" = 0;
      # With zram the swap is RAM: swap early and read a page back in one go.
      "vm.swappiness" = 150;
      "vm.page-cluster" = 0;
      "vm.vfs_cache_pressure" = 50;
      "kernel.nmi_watchdog" = 0;
    };

    # /dev/ntsync: Proton 10+ and GE-Proton use it instead of esync/fsync when it exists
    # (better frame pacing in CPU-heavy games). Mainline module, not loaded by default;
    # the device is world-accessible (0666), so no udev rule.
    boot.kernelModules = [ "ntsync" ];

    programs.gamemode = {
      enable = true;
      enableRenice = true;
      settings.general = {
        renice = 10;
        inhibit_screensaver = 1;
      };
    };
    # gamemode's polkit rule only lets the `gamemode` group run its root helpers
    # (CPU governor, split_lock_mitigate); without it every pkexec call is refused.
    users.users.${user.name}.extraGroups = [ "gamemode" ];
  };
}
