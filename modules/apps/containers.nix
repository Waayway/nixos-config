args@{ pkgs, tools, ... }:
tools.mkAppCategory args {
  name = "containers";
  apps = {
    # Docker Desktop: pkgs.docker is only the CLI/engine and won't run on macOS.
    docker.darwinCasks = [ "docker" ];
  };
}
