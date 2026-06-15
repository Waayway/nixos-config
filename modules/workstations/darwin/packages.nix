{ pkgs, ... }:
{
  # Cross-platform CLI tools migrated from the user's prior Homebrew install.
  # Anything Linux-specific (tlp, lm_sensors, pciutils, ...) stays in
  # `modules/base/packages.nix` for NixOS hosts only.
  environment.systemPackages = with pkgs; [
    fastfetch
    git
    nil
    nixd

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
    iperf3

    # Misc
    file
    findutils
    tree
    gnutar
    rsync
    just
    gettext

    # Migrated from brew formulae
    bat
    btop
    lsd
    ripgrep
    yt-dlp
    ffmpeg
    sqlite

    gnumake
  ];
}
