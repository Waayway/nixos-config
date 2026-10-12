{ pkgs, crane }:
let
  inherit (pkgs) lib;
  craneLib = crane.mkLib pkgs;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      (craneLib.fileset.commonCargoSources ./.)
      ./web/src/bindings
    ];
  };

  commonArgs = {
    pname = "fleet";
    version = "0.1.0";
    inherit src;
    strictDeps = true;
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

  mkBin =
    crate: extra:
    craneLib.buildPackage (
      commonArgs
      // {
        inherit cargoArtifacts;
        pname = crate;
        cargoExtraArgs = "-p ${crate}";
        doCheck = false;
      }
      // extra
    );

  # The dashboard bundle (Vite build output), embedded into fleet-server.
  fleet-web = pkgs.buildNpmPackage {
    pname = "fleet-web";
    version = "0.1.0";
    # Flake sources never contain the git-ignored node_modules/ and dist/.
    src = ./web;
    npmDepsHash = "sha256-Ry6RH2Kod1bShU3orxHvvsuGc3Hia3gmReZD7krChSs=";
    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };
in
{
  inherit fleet-web;
  fleet-agent = mkBin "fleet-agent" { };
  fleetctl = mkBin "fleetctl" { };
  fleet-server = mkBin "fleet-server" { FLEET_WEB_DIST = "${fleet-web}"; };

  bindingsCheck = craneLib.cargoTest (
    commonArgs
    // {
      inherit cargoArtifacts;
      pname = "fleet-bindings";
      cargoTestExtraArgs = "-p fleet-proto";
      preCheck = ''
        export TS_RS_EXPORT_DIR="$TMPDIR/b"
      '';
      postCheck = ''
        diff -r "$TMPDIR/b" web/src/bindings
      '';
    }
  );
}
