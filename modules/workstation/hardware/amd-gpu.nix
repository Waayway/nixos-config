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

    # LACT: Linux AMDGPU Controller
    environment.systemPackages = with pkgs; [ lact ];
    systemd.packages = with pkgs; [ lact ];
    systemd.services.lactd.wantedBy = [ "multi-user.target" ];

    systemd.tmpfiles.rules = [ "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}" ];
  };
}
