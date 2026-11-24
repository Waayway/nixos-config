{
  config,
  lib,
  hostPlatform,
  ...
}:
# Kokoro-FastAPI (remsky/Kokoro-FastAPI, OpenAI-compatible `/v1/audio/speech`) on prod's
# CPU, for the agent's livetalk voice on iris (`modules/server/agent/hermes.nix`,
# `tts.provider = "openai"`). CPU, not the passed-through Arc A380: OpenVINO's GPU (and
# CPU) EP can't compile Kokoro's graph at all (unsupported ops in this model's ONNX
# export), and PyTorch XPU finds zero Level Zero drivers on this nixpkgs — both dead
# ends unrelated to configuration. Plain CPU inference is the only path that produced
# audio when benchmarked on prod's own CPU (AMD Ryzen 9 5900X): short replies synthesize
# in a few hundred ms, well inside a livetalk turn. Details and numbers: docs/agent.md
# Voice section.
#
# The model and voice packs are baked into the published image at build time
# (upstream's Dockerfile runs its download script with `DOWNLOAD_MODEL=true` during the
# image build, verified by reading it); the same script reruns at container start but
# only checksums the files already on disk and returns immediately when they match, so
# no persistent volume is needed for restarts not to redownload. `HF_HUB_OFFLINE`
# disables the one remaining per-start network call (a telemetry-ish GET of the Hub's
# `config.json` to log if it drifted from the pinned digest — never required for
# inference).
#
# Only iris calls this (one LAN hop, same /24 as prod, no router/Traefik needed — see
# `homelab/lan.nix`): no `homelab.routes` entry. The port is restricted to iris's
# source address, the same `nixos-fw`/iptables pattern
# `modules/server/monitoring/agent.nix` uses to restrict exporter ports to the monitor
# VM only (narrower than jellyfin.nix/immich.nix's whole-LAN-interface `allowedTCPPorts`,
# appropriate here since this is a service-to-service hop, not a LAN-facing app). No
# auth: Kokoro-FastAPI has none built in; the source-IP restriction is the only control,
# noted here for the record (LAN only, unauthenticated).
#
# `address`/`port` are plain options (not just a `let` binding) so a satellite host's
# module evaluation can read them too, the same shape `homelab.monitoring.serverAddress`
# uses for the monitor VM's address — this repo has no flake-wide cross-host IP lookup,
# so the address is a hardcoded literal (prod's `hosts/servers/prod.nix` `netInterface.ip`),
# not derived.
let
  cfg = config.homelab.voiceTts;
  lan = config.homelab.lan;
  image = "ghcr.io/remsky/kokoro-fastapi-cpu:v0.10.0@sha256:f54c5960c2b9387f6349080a9944f8bc7e8cdb98a4ef9238cb0b0f9ff9795f44";
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.voiceTts = {
    enable = lib.mkEnableOption "Kokoro TTS (container, OpenAI-compatible) for the agent's voice";
    address = lib.mkOption {
      type = lib.types.str;
      default = "10.0.10.100";
      description = "LAN address of the host that runs voice-tts (prod); other hosts' agent config reads this to reach it.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8880;
      description = "Kokoro-FastAPI's documented default port.";
    };
    allowFrom = lib.mkOption {
      type = lib.types.str;
      default = "10.0.10.101"; # iris
      description = "The only LAN source address allowed to reach the port (iris, the agent host).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lan.address != null;
        message = "homelab.voiceTts needs homelab.lan.address (the host file's netInterface.ip).";
      }
      {
        assertion = lan.address == cfg.address;
        message = "homelab.voiceTts.address (${cfg.address}) must match this host's homelab.lan.address (${toString lan.address}).";
      }
    ];

    homelab.containers.enable = true;

    virtualisation.oci-containers.containers.voice-tts = {
      inherit image;
      networks = [ "voice-tts" ];
      ports = [ "${lan.address}:${toString cfg.port}:${toString cfg.port}" ];
      environment = {
        HF_HUB_OFFLINE = "1";
      };
      # Leaves 1 of prod's 4 vCPUs for Jellyfin/Immich's own transcode work so a burst of
      # TTS calls can't starve them; restart policy is the oci-containers default
      # (`Restart = "on-failure"`), same as every other container module here.
      extraOptions = [ "--cpus=3" ];
    };

    networking.firewall.extraCommands = "iptables -w -A nixos-fw -p tcp -s ${cfg.allowFrom} --dport ${toString cfg.port} -j nixos-fw-accept";
    networking.firewall.extraStopCommands = "iptables -w -D nixos-fw -p tcp -s ${cfg.allowFrom} --dport ${toString cfg.port} -j nixos-fw-accept || true";
  };
}
