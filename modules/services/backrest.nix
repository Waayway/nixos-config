{ user, ... }:

let
  base = "/home/${user.name}/backup";
in
{
  virtualisation.oci-containers.backend    = "docker";
  virtualisation.docker.enable             = true;
  virtualisation.docker.autoPrune.enable   = true;

  systemd.tmpfiles.rules = [
    "d ${base}                0750 ${user.name} ${user.name} - -"
    "d ${base}/data           0750 ${user.name} ${user.name} - -"
    "d ${base}/data/backrest  0700 ${user.name} ${user.name} - -"
    "d ${base}/cache          0750 ${user.name} ${user.name} - -"
    "d ${base}/cache/backrest 0700 ${user.name} ${user.name} - -"
    "d ${base}/scripts        0755 ${user.name} ${user.name} - -"
    "d ${base}/ssh            0700 root        root        - -"
  ];

  virtualisation.oci-containers.containers.backrest = {
    image     = "garethgeorge/backrest:v1.5.0";
    autoStart = true;
    environment = {
      BACKREST_PORT   = "0.0.0.0:9898";
      BACKREST_DATA   = "/data";
      BACKREST_CONFIG = "/data/config.json";
      XDG_CACHE_HOME  = "/cache";
      TZ              = "Europe/Amsterdam";
    };
    volumes = [
      "${base}/data/backrest:/data"
      "${base}/cache/backrest:/cache"
      "${base}/scripts:/scripts:ro"
      "${base}/ssh:/root/.ssh:ro"
    ];
    ports        = [ "9898:9898" ];
    extraOptions = [ "--hostname=backrest" ];
  };

  virtualisation.oci-containers.containers.backrest-browser = {
    image           = "ghcr.io/waayway/backrest-browser:latest";
    autoStart       = true;
    environment.TZ  = "Europe/Amsterdam";
    volumes         = [ "${base}/ssh:/root/.ssh:ro" ];
    ports           = [ "9899:8080" ];
    extraOptions    = [ "--hostname=backrest-browser" ];
  };

  # oci-containers can't bind a host IP per-port. Restrict via firewall instead.
  networking.firewall.interfaces.ens18.allowedTCPPorts = [ 9898 9899 ];
}
