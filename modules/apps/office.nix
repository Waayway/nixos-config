args@{ pkgs, tools, ... }:
tools.mkAppCategory args {
  name = "office";
  apps = {
    libreoffice.linux = [ pkgs.libreoffice ];
    microsoft365.darwinCasks = [
      "microsoft-word"
      "microsoft-excel"
      "microsoft-powerpoint"
      "microsoft-outlook"
      "microsoft-onenote"
      "microsoft-teams"
    ];
    onedrive.darwinCasks = [ "onedrive" ];
    google-drive.darwinCasks = [ "google-drive" ];
    obsidian = {
      linux = [ pkgs.obsidian ];
      darwinCasks = [ "obsidian" ];
    };
  };
}
