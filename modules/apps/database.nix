args@{ pkgs, ... }:
import ../../lib/mkAppCategory.nix args {
  name = "database";
  apps = {
    pgadmin.darwinCasks = [ "pgadmin4" ];
    sqlitebrowser = {
      linux = [ pkgs.sqlitebrowser ];
      darwinCasks = [ "db-browser-for-sqlite" ];
    };
  };
}
