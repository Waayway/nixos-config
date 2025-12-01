{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.bluetooth;
in
{
  options.bluetooth = {
    enable = mkEnableOption "bluetooth";
  };

  config = mkIf cfg.enable {
		boot.kernelModules = [ "btusb" ];

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
				General = {
					#Enable = "Source,Sink,Media,Socket";
					Experimental = true;
					FastConnectable = true;
				};
			  Policy = {
					AutoEnable = true;
				};
			};
    };
    services.blueman.enable = true;

    systemd.user.services.mpris-proxy = {
      enable = true;
    };
    environment.systemPackages = with pkgs; [
      blueberry
    ];
  };
}
