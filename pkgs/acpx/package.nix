{
  lib,
  buildNpmPackage,
  fetchurl,
}:
let
  version = "0.22.0";
in
buildNpmPackage {
  pname = "acpx";
  inherit version;

  # Upstream (openclaw/acpx) ships a pnpm-lock.yaml and a devDependency-heavy
  # monorepo (vite, stryker, oxlint's native toolchain, …) that buildNpmPackage
  # can't resolve. The published tarball already carries the built `dist/`, so
  # fetch it directly and vendor a slim package.json + package-lock.json with
  # only the published runtime dependencies (package.nix:postPatch).
  src = fetchurl {
    url = "https://registry.npmjs.org/acpx/-/acpx-${version}.tgz";
    hash = "sha512-dD+xgRwLFOfwL7/VEdn3zrVNFleFoIA0EUETK35w/e+MeYB5FN5+vKERoV60d4SUirTqX610yb/wN+2OFcjpMQ==";
  };

  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-yl3m2d68qkZsoYuV30jyeBoEg10zpm023vZxsUQAH0c=";

  dontNpmBuild = true;

  meta = {
    description = "Headless CLI client for the Agent Client Protocol (ACP)";
    homepage = "https://github.com/openclaw/acpx";
    license = lib.licenses.mit;
    mainProgram = "acpx";
  };
}
