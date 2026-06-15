{ pkgs, lib, isLinux, isFramework, ... }:
{
  environment.systemPackages =
    with pkgs;
    # Cross-platform: usable on NixOS and nix-darwin alike.
    [
      fastfetch
      git
      lsof
      btop

      # Archives
      zip
      xz
      zstd
      unzip
      p7zip

      # Text processing
      gnugrep
      gnused
      gawk
      jq

      # Networking tools
      dnsutils
      wget
      curl
      nmap

      # Misc
      file
      findutils
      which
      tree
      gnutar
      rsync
      gnumake
    ]
    # Linux-only tools (kernel tracing, hardware probes, GNU sysadmin tools
    # that don't exist or don't make sense on darwin).
    ++ lib.optionals isLinux (with pkgs; [
      strace
      ltrace
      bpftrace
      tcpdump

      sysstat
      iotop
      iftop
      nmon
      sysbench

      psmisc
      lm_sensors
      ethtool
      pciutils
      usbutils
      hdparm
      dmidecode
      parted

      gcc
    ])
    ++ lib.optionals isFramework [ pkgs.framework-tool ];

  environment.variables = {
    EDITOR = "nvim";
  } // lib.optionalAttrs isLinux {
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
  };
}
