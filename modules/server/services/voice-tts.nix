{
  config,
  lib,
  pkgs,
  hostPlatform,
  ...
}:
# Kokoro TTS (OpenAI-compatible `/v1/audio/speech`, pkgs/kokoro-tts) on prod's GPU via
# Vulkan (onnxruntime's WebGPU execution provider, Dawn -> Vulkan on the Arc A380), for
# the agent's livetalk voice on iris (`modules/server/agent/hermes.nix`,
# `tts.provider = "openai"`). Replaces commit 2's Kokoro-FastAPI CPU container: w6's
# report proved WebGPU genuinely beats CPU on this box (medium-text RTF 0.197-0.198 vs
# CPU's 0.230-0.255) while freeing nearly all of the CPU for Jellyfin/Immich. Details:
# docs/agent.md Voice section, w6-report.md.
#
# `gpu` (default true, set on prod in hosts/servers/prod.nix) switches both the
# onnxruntime provider list (server.py's KOKORO_GPU env var) and this unit's GPU wiring
# (device cgroup access, VK_ICD_FILENAMES, the Vulkan loader on LD_LIBRARY_PATH); off
# runs CPU-only, with no GPU device access requested at all -- used for iris's own
# loopback smoke test (iris has no GPU; see b3-report.md), not expected on prod.
#
# Only iris calls this (one LAN hop, same /24 as prod, no router/Traefik needed -- see
# `homelab/lan.nix`): no `homelab.routes` entry. The port is restricted to iris's
# source address, the same `nixos-fw`/iptables pattern
# `modules/server/monitoring/agent.nix` uses to restrict exporter ports to the monitor
# VM only (narrower than jellyfin.nix/immich.nix's whole-LAN-interface
# `allowedTCPPorts`, appropriate here since this is a service-to-service hop, not a
# LAN-facing app). No auth: the server has none built in; the source-IP restriction is
# the only control, noted here for the record (LAN only, unauthenticated), same as
# before.
#
# `address`/`port` are plain options (not just a `let` binding) so a satellite host's
# module evaluation can read them too, the same shape `homelab.monitoring.serverAddress`
# uses for the monitor VM's address -- this repo has no flake-wide cross-host IP lookup,
# so the address is a hardcoded literal (prod's `hosts/servers/prod.nix`
# `netInterface.ip`), not derived. Port and option names are kept exactly as commit 2's
# container had them, so iris's side of the wiring doesn't change at all.
let
  cfg = config.homelab.voiceTts;
  lan = config.homelab.lan;
  server = pkgs.kokoro-tts-server;
in
lib.optionalAttrs hostPlatform.isLinux {
  options.homelab.voiceTts = {
    enable = lib.mkEnableOption "Kokoro TTS (OpenAI-compatible, onnxruntime WebGPU/CPU) for the agent's voice";
    address = lib.mkOption {
      type = lib.types.str;
      default = "10.0.10.100";
      description = "LAN address of the host that runs voice-tts (prod); other hosts' agent config reads this to reach it.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8880;
      description = "Kokoro-FastAPI's documented default port; kept as this service's port too so iris's base_url doesn't change.";
    };
    allowFrom = lib.mkOption {
      type = lib.types.str;
      default = "10.0.10.101"; # iris
      description = "The only LAN source address allowed to reach the port (iris, the agent host).";
    };
    defaultVoice = lib.mkOption {
      type = lib.types.str;
      default = "af_heart";
      description = "Default voice (or Kokoro-FastAPI-style blend, e.g. \"af_heart(0.7)+af_nova(0.3)\") for requests that omit one. Any voice in voices-v1.0.bin is selectable per request (GET /v1/audio/voices lists them); this is a one-line setting to change later, not a hard limit.";
    };
    gpu = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run onnxruntime's WebGPU execution provider on the passed-through Arc A380 (Vulkan via Mesa ANV). Off: CPU-only, no GPU device access requested (iris's own smoke test; iris has no GPU).";
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

    hardware.graphics.enable = lib.mkIf cfg.gpu true;

    systemd.services.voice-tts = {
      description = "Kokoro TTS (OpenAI-compatible /v1/audio/speech)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${server}/bin/kokoro-tts-server";
        Restart = "on-failure";
        RestartSec = "2s";

        DynamicUser = true;
        SupplementaryGroups = lib.mkIf cfg.gpu [
          "render"
          "video"
        ];
        # For XDG_RUNTIME_DIR below: a private, DynamicUser-owned dir under /run.
        RuntimeDirectory = "voice-tts";
        # Leaves 1 of prod's 4 vCPUs for Jellyfin/Immich's own transcode work, same
        # rationale (and the same cap) as commit 2's container `--cpus=3`; applies
        # whether or not `gpu` is on, since the per-node CPU fallback ops (w6: ~439 of
        # ~2254 graph nodes) still run on every request even with WebGPU active.
        CPUQuota = "300%";

        Environment = [
          "KOKORO_HOST=${lan.address}"
          "KOKORO_PORT=${toString cfg.port}"
          "KOKORO_GPU=${if cfg.gpu then "1" else "0"}"
          "KOKORO_DEFAULT_VOICE=${cfg.defaultVoice}"
          "XDG_RUNTIME_DIR=%t/voice-tts"
        ]
        ++ lib.optionals cfg.gpu [
          "VK_ICD_FILENAMES=${config.hardware.graphics.package}/share/vulkan/icd.d/intel_icd.x86_64.json"
          # Unavoidable: `libvulkan.so.1` is dlopen'd by onnxruntime's WebGPU EP at
          # runtime, not a declared NEEDED library (confirmed: `patchelf
          # --print-needed` on the wheel's .so files lists only libc/libstdc++;
          # `strings libonnxruntime.so | grep libvulkan` finds the dlopen literal) --
          # autoPatchelfHook (pkgs/kokoro-tts/onnxruntime-webgpu.nix) can only fix
          # declared NEEDED entries, not dlopen targets.
          "LD_LIBRARY_PATH=${pkgs.vulkan-loader}/lib"
        ];

        # Hardening, in the style of the repo's other long-running services.
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        # The kernel side of /dev/dri access (cgroup device filter); the Unix
        # permission bits that decide which actual nodes (renderD128 vs card0) are
        # openable come from SupplementaryGroups above, same split as jellyfin.nix's
        # container equivalent (`--group-add=render/video` + `/dev/dri` passthrough).
        DeviceAllow = lib.mkIf cfg.gpu [ "char-drm rw" ];
      };
    };

    networking.firewall.extraCommands = "iptables -w -A nixos-fw -p tcp -s ${cfg.allowFrom} --dport ${toString cfg.port} -j nixos-fw-accept";
    networking.firewall.extraStopCommands = "iptables -w -D nixos-fw -p tcp -s ${cfg.allowFrom} --dport ${toString cfg.port} -j nixos-fw-accept || true";
  };
}
