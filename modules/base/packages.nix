{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    fastfetch
    neovim
    git

    strace
    ltrace
    bpftrace
    tcpdump
    lsof

    sysstat
    iotop
    iftop
    btop
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

    # networking tools
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
  ];

  environment.variables.PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";

  environment.variables.EDITOR = "nvim";
}
