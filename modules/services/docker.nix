{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# What the container apps in this folder (nextcloud.nix, jellyfin.nix, immich.nix)
# share: the Docker engine as the `virtualisation.oci-containers` backend, one bridge
# network per app (containers reach each other by name, as in a compose project),
# `RequiresMountsFor` on every container that binds a path from TrueNAS, nightly
# database dumps, and the Intel GPU (Arc A380) for the apps that ask for it.
let
  cfg = config.homelab.containers;
  containers = config.virtualisation.oci-containers.containers;
  docker = config.virtualisation.docker.package;

  # Docker's own networks; everything else is created by `docker-network-<name>`.
  builtinNetworks = [
    "bridge"
    "host"
    "none"
  ];
  ownNetworks = c: lib.subtractLists builtinNetworks c.networks;
  networks = lib.unique (lib.concatMap ownNetworks (lib.attrValues containers));

  # Host side of `-v host:container[:opts]` when it is on an NFS mount.
  nfsPaths =
    c:
    lib.filter (p: lib.hasPrefix "/store/" p || lib.hasPrefix "/archive/" p) (
      map (v: lib.head (lib.splitString ":" v)) c.volumes
    );

  dumpDir = app: "/store/db-dumps/${app}";

  dumpService =
    app: d:
    lib.nameValuePair "${app}-db-dump" {
      description = "Dump the ${app} database to ${dumpDir app}";
      after = [ "${containers.${d.container}.serviceName}.service" ];
      unitConfig.RequiresMountsFor = [ (dumpDir app) ];
      path = [
        docker
        pkgs.coreutils
        pkgs.findutils
        pkgs.gzip
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -euo pipefail
        dir=${dumpDir app}
        out="$dir/${app}-$(date +%F).sql.gz"
        docker exec ${d.container} sh -c ${lib.escapeShellArg d.command} | gzip >"$out.tmp"
        mv "$out.tmp" "$out"
        # Keep the newest ${toString d.keep} (the names sort by date).
        printf '%s\n' "$dir"/${app}-*.sql.gz | sort -r | tail -n +${toString (d.keep + 1)} | xargs -r rm -f --
      '';
    };
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.containers = {
    enable = lib.mkEnableOption "the Docker engine for the homelab's container apps";

    dumps = lib.mkOption {
      default = { };
      description = ''
        Nightly (01:30) database dumps, keyed by app: `<app>-db-dump` runs `command`
        in `container` and writes its output gzipped to
        `/store/db-dumps/<app>/<app>-<date>.sql.gz`, keeping the newest `keep`.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            container = lib.mkOption {
              type = lib.types.str;
              description = "The database container (a `virtualisation.oci-containers` name).";
            };
            command = lib.mkOption {
              type = lib.types.str;
              description = "Shell command run with `sh -c` in the container; writes the dump to stdout.";
            };
            keep = lib.mkOption {
              type = lib.types.ints.positive;
              default = 14;
              description = "Number of dumps kept.";
            };
          };
        }
      );
    };

    intelGpu = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The passed-through Intel Arc A380 (QSV / VA-API, iHD driver): firmware, GuC/HuC
        and the media driver on the host. Set by the app modules' `gpu` options.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        virtualisation.docker = {
          enable = true;
          # Images left behind by the weekly updates.
          autoPrune = {
            enable = true;
            dates = "weekly";
          };
        };
        virtualisation.oci-containers.backend = "docker";

        systemd.services = lib.mkMerge [
          # One bridge network per app.
          (lib.listToAttrs (
            map (
              net:
              lib.nameValuePair "docker-network-${net}" {
                description = "Docker network ${net}";
                after = [
                  "docker.service"
                  "docker.socket"
                ];
                requires = [ "docker.service" ];
                path = [ docker ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
                script = "docker network inspect ${net} >/dev/null 2>&1 || docker network create ${net}";
              }
            ) networks
          ))

          # Containers wait for their networks and for the TrueNAS paths they bind.
          (lib.mapAttrs' (
            _: c:
            lib.nameValuePair c.serviceName {
              after = map (n: "docker-network-${n}.service") (ownNetworks c);
              requires = map (n: "docker-network-${n}.service") (ownNetworks c);
              unitConfig.RequiresMountsFor = nfsPaths c;
            }
          ) containers)

          (lib.mapAttrs' dumpService cfg.dumps)
        ];

        systemd.timers = lib.mapAttrs' (
          app: _:
          lib.nameValuePair "${app}-db-dump" {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "01:30";
              Persistent = true;
            };
          }
        ) cfg.dumps;
      }

      (lib.mkIf cfg.intelGpu {
        # The containers bring their own iHD/oneVPL userspace; the host needs the
        # GuC/HuC firmware and the kernel side. The packages give `vainfo` here.
        hardware.enableRedistributableFirmware = true;
        boot.kernelParams = [ "i915.enable_guc=3" ];
        hardware.graphics = {
          enable = true;
          extraPackages = [
            pkgs.intel-media-driver
            pkgs.vpl-gpu-rt
          ];
        };
        environment.systemPackages = [ pkgs.libva-utils ];
      })
    ]
  );
}
