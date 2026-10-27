{
  lib,
  hostPlatform,
  ...
}:
lib.optionalAttrs hostPlatform.isLinux {
  # Framework laptops only (type = "framework…"): fw-fanctrl drives the fan
  # through the EC (ectool) with a temperature curve instead of the EC's own,
  # which on the AMD boards spins up hard and drops off again. The Quickshell
  # bar shows temperature/fan and switches strategies (`fw-fanctrl use <name>`;
  # the service's socket is open to users).
  # Strategies: https://github.com/TamtamHero/fw-fanctrl/blob/main/doc/configuration.md
  config = lib.mkIf (!hostPlatform.isServer && hostPlatform.isFramework) {
    hardware.fw-fanctrl = {
      enable = true;
      config = {
        # Keep the CPU around 60 °C (the stock curves let it reach 75-85 °C
        # before going loud). fw-fanctrl uses min(current, moving average), so
        # a short average and fast updates keep it from lagging behind.
        defaultStrategy = "cool";
        strategyOnDischarging = "cool";
        strategies.cool = {
          fanSpeedUpdateFrequency = 2;
          movingAverageInterval = 10;
          speedCurve = [
            {
              temp = 0;
              speed = 15;
            }
            {
              temp = 40;
              speed = 15;
            }
            {
              temp = 48;
              speed = 30;
            }
            {
              temp = 54;
              speed = 50;
            }
            {
              temp = 58;
              speed = 75;
            }
            {
              temp = 62;
              speed = 100;
            }
          ];
        };
      };
    };
  };
}
