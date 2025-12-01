{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [

    # -- Spotify --
    spotify # Has some issues so spot
    spot

    # -- Recording --
    obs-studio

    # -- Image --
    gimp
    krita

    # -- Video --
    mpv

		# -- Linux isos --
		qbittorrent

    # -- Vector
    inkscape
    figma-linux

    # -- Isos --
    popsicle
  ];
}
