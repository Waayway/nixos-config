# Bitfocus Companion 5.1.3, packaged here because nixpkgs-unstable is still on 5.0.5.
# Based on nixpkgs' pkgs/by-name/bi/bitfocus-companion/package.nix (MIT, maintainer
# tiebe); changed: the version and hashes, the bundled Stream Deck surface module (the
# URL moved; dart-sass and its patch are gone because the web UI dropped sass-embedded;
# the new legal-artifact step of the build script is skipped), and
# companion-missing-hashes.json, regenerated for this release's yarn.lock
# with `yarn-berry-fetcher missing-hashes yarn.lock` (the one in nixpkgs is for 5.0.5).
#
# To update: bump `version`, the source hash and the two surface modules from
# assets/builtin-surface-modules.json in the release (tarSha is hex; convert with
# `nix hash convert --hash-algo sha256 --from base16`), regenerate the missing hashes,
# set the offline cache hash to lib.fakeHash and copy the real one from the build error.
# Delete this file, and the callPackage in streamdeck.nix, once nixpkgs catches up.
# `_lib.nix` keeps it from being imported as a module.
{
  stdenv,
  lib,
  fetchFromGitHub,
  fetchurl,
  nodejs_26,
  git,
  python3,
  udev,
  yarn-berry_4,
  libusb1,
  electron,
  makeWrapper,
}:

let
  yarn-berry = yarn-berry_4;

  builtinSurfaces = {
    elgato-stream-deck = fetchurl {
      url = "https://developer-module-builds.s4.bitfocus.io/surface/elgato-stream-deck/v1.5.3-b7816a7b0c12-cd2da536da8d/elgato-stream-deck-v1.5.3.tgz";
      hash = "sha256-zS2lNtqNK5u9hRNmGH4NiIFiNx2xxwa5bKfwAAZ10RE=";
    };
    xkeys = fetchurl {
      url = "https://developer-module-builds.s4.bitfocus.io/surface/xkeys/v1.0.2-876f00ee194faa57ec14468b7019bbaa516a9e6d/xkeys-v1.0.2.tgz";
      hash = "sha256-LYJD0Wb90hIIs8AIiZoqLxxKtMWko9rryPSds9ZYCac=";
    };
  };

  selectSystem =
    attrs:
    attrs.${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}");
  platform = selectSystem {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    armv7l-linux = "linux-armv7l";
  };
in

stdenv.mkDerivation rec {
  pname = "bitfocus-companion";
  version = "5.1.3";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "bitfocus";
    repo = "companion";
    tag = "v${version}";
    hash = "sha256-drg4hvKL2yB+kg4BjOo7yg38UgOE0gUupMee4PAQD2w=";
  };

  postPatch = ''
    # patch out git calls to generate version strings.
    substituteInPlace tools/lib.mts --replace-fail "return await fcn()" "return \"v${version}\" as unknown as T"

    # remove yarn config options which require network access at install time
    printf "nodeLinker: node-modules\nenableScripts: false\n" > .yarnrc.yml

    # remove the yarn install during the build, since there is no internet connection, and everything has already been installed by yarnBerryConfigHook
    substituteInPlace tools/build/package.mts --replace-fail "await $\`yarn install --no-immutable\`" ""

    # 5.1.x writes dist/LICENSE and dist/NOTICE from dist/node_modules, which only exists
    # after the `yarn install` removed above; the Nix build uses the top-level node_modules
    # (NODE_PATH below), so there is nothing to scan and the files are not needed.
    substituteInPlace tools/build/package.mts \
      --replace-fail "await generateLegalArtifacts('dist')" ""

    # remove node download, since we'll use the nix version
    substituteInPlace tools/build/package.mts \
      --replace-fail "const nodeVersions = await fetchNodejs(platformInfo)" "const nodeVersions: [string, string][] = []" \
      --replace-fail "await fs.createSymlink(latestRuntimeDir, path.join(runtimesDir, 'main'), 'dir')" ""

    substituteInPlace companion/lib/Instance/NodePath.ts \
      --replace-fail "if (!(await fs.pathExists(nodePath))) return null" "return '${lib.getExe nodejs_26}'"
    # every module runs on node 26 here (above), whose permission model also blocks the
    # network; upstream only skips --allow-net for node22 modules because they get node 22,
    # so without this the node22 ones (discord-api, most of the store) can't connect
    substituteInPlace companion/lib/Instance/NodePath.ts \
      --replace-fail "if (manifest.runtime.type !== 'node22') args.push('--allow-net')" "args.push('--allow-net')"

    # allow all surface modules (builtin and user-downloaded) to find libudev, by adding
    # LD_LIBRARY_PATH to the env whitelist companion uses when spawning module child processes
    substituteInPlace companion/lib/Instance/Environment.ts \
      --replace-fail "'DISABLE_IPV6'," "'DISABLE_IPV6', 'LD_LIBRARY_PATH',"
  '';

  nativeBuildInputs = [
    nodejs_26
    yarn-berry.yarnBerryConfigHook
    git
    python3
    yarn-berry
    makeWrapper
  ];

  buildInputs = [
    libusb1
    nodejs_26
    electron
    udev
  ];

  missingHashes = ./companion-missing-hashes.json;

  offlineCache = yarn-berry.fetchYarnBerryDeps {
    inherit src missingHashes;
    hash = "sha256-tUSNx846Lc3Gjgd+mgUfWFmsYgbnrDtd2aW1d2VhcUk=";
  };

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = 1;
    SKIP_LAUNCH_CHECK = true;
    ELECTRON = 0;
  };

  # with dontConfigure it doesn't seem to retrieve node_modules, so empty configurePhase instead
  configurePhase = ''
    runHook preConfigure
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    # pre-populate builtin surface module cache to avoid network access during build
    mkdir -p .cache/builtin-surfaces/elgato-stream-deck
    tar -xzf ${builtinSurfaces.elgato-stream-deck} --strip-components=1 -C .cache/builtin-surfaces/elgato-stream-deck
    mkdir -p .cache/builtin-surfaces/xkeys
    tar -xzf ${builtinSurfaces.xkeys} --strip-components=1 -C .cache/builtin-surfaces/xkeys
    sha256sum assets/builtin-surface-modules.json | awk '{print $1}' > .cache/builtin-surfaces-checksum.txt

    yarn dist ${platform}

    runHook postBuild
  '';

  preInstall = ''
    # remove node runtime, since we will always use the nix node runtime
    rm -rf .cache/node-runtimes
    rm -rf dist/node-runtimes
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/bitfocus-companion
    cp -r * $out/share/bitfocus-companion/

    makeWrapper ${lib.getExe nodejs_26} $out/bin/bitfocus-companion \
      --add-flags $out/share/bitfocus-companion/dist/main.js \
      --set LD_LIBRARY_PATH "${
        lib.makeLibraryPath [
          libusb1
          udev
        ]
      }" \
      --set NODE_PATH $out/share/bitfocus-companion/node_modules

    runHook postInstall
  '';

  meta = {
    description = "Program for controlling Stream Deck devices";
    longDescription = "Bitfocus Companion enables the Elgato Stream Deck and other controllers to be a professional shotbox surface for an increasing amount of different presentation switchers, video playback software and broadcast equipment.";
    homepage = "https://bitfocus.io/companion";
    license = lib.licenses.mit;
    mainProgram = "bitfocus-companion";
    platforms = lib.platforms.linux;
  };
}
