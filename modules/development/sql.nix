{
  pkgs,
  lib,
  hostPlatform,
  user,
  ...
}:
let
  # Homebrew, not nix: venvs compile psycopg2 against libpq, and these
  # /opt/homebrew/opt paths survive upgrades and nix garbage collection.
  pg = "/opt/homebrew/opt/postgresql@18";
  dataDir = "/opt/homebrew/var/postgresql@18";
  logFile = "/opt/homebrew/var/log/postgresql@18.log";
in
{
  config = lib.mkMerge [
    {
      environment.systemPackages = with pkgs; [
        sql-studio
      ];
    }

    (lib.optionalAttrs hostPlatform.isDarwin {
      # Local Postgres for development. pgvector builds for @17 and @18.
      homebrew.brews = [
        "postgresql@18"
        "pgvector"
      ];

      environment.systemPath = [ "${pg}/bin" ];
      environment.variables.PKG_CONFIG_PATH = [ "/opt/homebrew/lib/postgresql@18/pkgconfig" ];

      # Cluster owned by the login user (its superuser), trust auth on the
      # socket and localhost, socket in /tmp where psql and Odoo look for it.
      system.activationScripts.postActivation.text = ''
        if [ -x ${pg}/bin/initdb ] && [ ! -f ${dataDir}/PG_VERSION ]; then
          echo "initializing PostgreSQL 18 cluster..." >&2
          sudo --user=${user.name} -- env LC_ALL=en_US.UTF-8 ${pg}/bin/initdb \
            --locale=en_US.UTF-8 -E UTF-8 --auth=trust -U ${user.name} -D ${dataDir}
          launchctl kickstart -k "gui/$(id -u -- ${user.name})/org.nixos.postgresql" 2>/dev/null || true
        fi
      '';

      launchd.user.agents.postgresql.serviceConfig = {
        ProgramArguments = [
          "${pg}/bin/postgres"
          "-D"
          dataDir
          "-p"
          "5432"
          "-k"
          "/tmp"
        ];
        EnvironmentVariables.LC_ALL = "en_US.UTF-8";
        RunAtLoad = true;
        # Restart on crash only: a stale postmaster.pid makes postgres exit 1.
        KeepAlive.SuccessfulExit = false;
        StandardOutPath = logFile;
        StandardErrorPath = logFile;
        WorkingDirectory = "/opt/homebrew";
      };
    })
  ];
}
