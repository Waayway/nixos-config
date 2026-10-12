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
    crate:
    craneLib.buildPackage (
      commonArgs
      // {
        inherit cargoArtifacts;
        pname = crate;
        cargoExtraArgs = "-p ${crate}";
        doCheck = false;
      }
    );
in
{
  fleet-agent = mkBin "fleet-agent";
  # Stub until Task 9.
  fleet-server = mkBin "fleet-server";
  # Stub until Task 14.
  fleet-web = pkgs.runCommand "fleet-web" { } "mkdir -p $out";

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
