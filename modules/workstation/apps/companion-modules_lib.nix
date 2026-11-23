# The Companion modules from github:Waayway/companion-modules (flake input
# `companion-modules`): `mangohud` and `linux-media`. Each is a Yarn 4 TypeScript project;
# this builds dist/ and installs it with its node_modules into $out/<module>/, the layout
# Companion's `--extra-module-path` scans (<dir>/<module>/companion/manifest.json).
# streamdeck.nix passes $out to Companion.
#
# After `nix flake update companion-modules`, if a module's yarn.lock changed: regenerate
# companion-modules-<module>-missing-hashes.json (esbuild's per-platform packages) with
# `yarn-berry-fetcher missing-hashes yarn.lock`, set its hash to lib.fakeHash and copy the
# real one from the build error.
# `_lib.nix` keeps it from being imported as a module.
{
  lib,
  stdenvNoCC,
  linkFarm,
  nodejs_26,
  yarn-berry_4,
  src,
}:
let
  yarn-berry = yarn-berry_4;

  mkModule =
    name: hash:
    stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "companion-module-${name}";
      version = "0.1.0-${src.shortRev or "dirty"}";
      src = "${src}/modules/${name}";

      nativeBuildInputs = [
        nodejs_26
        yarn-berry
        yarn-berry.yarnBerryConfigHook
      ];

      missingHashes = ./companion-modules-${name}-missing-hashes.json;
      offlineCache = yarn-berry.fetchYarnBerryDeps {
        inherit (finalAttrs) src missingHashes;
        inherit hash;
      };

      buildPhase = ''
        runHook preBuild
        yarn build
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r companion dist node_modules package.json $out/
        # the tests are compiled too; Companion doesn't need them
        find $out/dist -name '*.test.js' -delete
        runHook postInstall
      '';

      meta = {
        description = "Bitfocus Companion module ${name}";
        homepage = "https://github.com/Waayway/companion-modules";
        license = lib.licenses.mit;
        platforms = lib.platforms.linux;
      };
    });
in
linkFarm "companion-modules" {
  mangohud = mkModule "mangohud" "sha256-2i8DlgvYDZrU0ZqTKdafxJqYihggc8PwHpmt5RohEcY=";
  linux-media = mkModule "linux-media" "sha256-v9fO45fUp5DYJoe80nDyODe6QNLbjViYCU09faBOos8=";
}
