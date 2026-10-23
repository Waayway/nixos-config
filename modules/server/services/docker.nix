{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# What the container apps in this folder (nextcloud.nix, jellyfin.nix, immich.nix)
# share: the Docker engine as the `virtualisation.oci-containers` backend, one bridge
# network per app (containers reach each other by name, as in a compose project; each
# container's unit creates it), `RequiresMountsFor` on every container that binds a
# path from TrueNAS, nightly database dumps, and the Intel GPU (Arc A380) for the apps
# that ask for it.
let
  cfg = config.homelab.containers;
  containers = config.virtualisation.oci-containers.containers;
  docker = config.virtualisation.docker.package;

  # Docker's own networks; every other network a container names is created by the
  # container's own unit before `docker run` (`ensureNetworks`).
  builtinNetworks = [
    "bridge"
    "host"
    "none"
  ];
  ownNetworks = c: lib.subtractLists builtinNetworks c.networks;

  # Not a separate oneshot unit: the weekly `docker system prune` (autoPrune) removes
  # networks no running container uses, and a oneshot with RemainAfterExit would still
  # count as active, so a container started after a prune would find its network gone.
  # Created on every start instead; the trailing inspect tolerates two containers of one
  # app creating it at the same moment.
  ensureNetworks =
    name: c:
    pkgs.writeShellScript "docker-${name}-networks" (
      lib.concatMapStrings (net: ''
        ${lib.getExe docker} network inspect ${net} >/dev/null 2>&1 ||
          ${lib.getExe docker} network create ${net} >/dev/null ||
          ${lib.getExe docker} network inspect ${net} >/dev/null
      '') (ownNetworks c)
    );

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
      serviceConfig = {
        Type = "oneshot";
        # Dumps hold every password hash and file share: owner-only on TrueNAS.
        UMask = "0077";
      };
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

    floating = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "nextcloud:32-apache" ];
      description = ''
        Images that follow a floating tag (a minor track such as `nextcloud:32-apache`).
        The weekly update (`prod-container-update`, updates.nix) pulls only these and
        restarts the containers whose image changed; Renovate proposes only major
        updates for them (renovate.json lists the same images). Every other image is
        pinned and changes through a Renovate pull request.
      '';
    };

    intelGpu = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The passed-through Intel Arc A380 (QSV / VA-API, iHD driver): GuC/HuC and
        `vainfo` on the host; the host side comes from the nixos-hardware
        `common-gpu-intel` profile. Set by the app modules' `gpu` options.
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

        # Per-container metrics for the Grafana "Docker / cAdvisor" dashboard (grafana.com 14282).
        services.cadvisor = {
          enable = true;
          listenAddress = "0.0.0.0";
          port = 9101;
          # cAdvisor reaches Docker through containerd; NixOS's Docker runs its own
          # containerd on this socket (namespace moby). Without it containers have no names.
          extraOptions = [
            "--containerd=/run/docker/containerd/containerd.sock"
            "--containerd-namespace=moby"
          ];
        };
        homelab.monitoring.targets.cadvisor.port = 9101;

        systemd.services = lib.mkMerge [
          # Containers create their networks and wait for the TrueNAS paths they bind.
          (lib.mapAttrs' (
            name: c:
            lib.nameValuePair c.serviceName {
              serviceConfig.ExecStartPre = lib.mkIf (ownNetworks c != [ ]) (
                lib.mkBefore [ "${ensureNetworks name c}" ]
              );
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
        # kernel side. The nixos-hardware profile adds the userspace packages.
        boot.kernelParams = [ "i915.enable_guc=3" ];
        # Stays here: the common-gpu-intel profile doesn't enable graphics itself.
        hardware.graphics.enable = true;
        environment.systemPackages = [ pkgs.libva-utils ];
      })
    ]
  );
}
