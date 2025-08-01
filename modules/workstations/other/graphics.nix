{ pkgs, ... }:
{
  hardware.enableRedistributableFirmware = true;

  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.amdgpu.opencl.enable = true;

  hardware.amdgpu.amdvlk = {
    enable = true;
    support32Bit.enable = true;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      rocmPackages.rocm-smi
      rocmPackages.clr.icd
      mesa
    ];
  };

  # Lact: Linux Amdgpu ConTroller
  environment.systemPackages = with pkgs; [ lact ];
  systemd.packages = with pkgs; [ lact ];
  systemd.services.lactd.wantedBy = [ "multi-user.target" ];

  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];
}
