args@{ pkgs, ... }:
import ../../lib/mkAppCategory.nix args {
  name = "containers";
  apps = {
    # Docker Desktop: pkgs.docker is only the CLI/engine and won't run on macOS.
    docker.darwinCasks = [ "docker" ];
  };
}
