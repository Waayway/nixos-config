{
  config,
  pkgs,
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  # The driver itself comes from the host's nixos-hardware profile
  # (common-gpu-amd); this adds ROCm OpenCL and LACT on top.
  options.hardware.amdgpu.extras.enable = lib.mkEnableOption "ROCm OpenCL and LACT for an AMD GPU";

  config = lib.mkIf config.hardware.amdgpu.extras.enable {
    hardware.amdgpu.opencl.enable = true;

    hardware.graphics.extraPackages = with pkgs; [
      rocmPackages.rocm-smi
      rocmPackages.clr.icd
    ];

    environment.systemPackages = with pkgs; [
      # LACT: Linux AMDGPU Controller
      lact
      # btop shows AMD GPUs only when built with ROCm SMI (it dlopens librocm_smi64);
      # wins over the plain btop from common/packages.
      (lib.hiPrio (btop.override { rocmSupport = true; }))
    ];
    systemd.packages = with pkgs; [ lact ];
    systemd.services.lactd.wantedBy = [ "multi-user.target" ];

    systemd.tmpfiles.rules = [ "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}" ];
  };
}
