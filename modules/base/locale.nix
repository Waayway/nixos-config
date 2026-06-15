{ config, lib, isLinux ? true, ... }:
let locale = config.modules.locale;
in {
  options.modules.locale = {
    timeZone = lib.mkOption {
      type = lib.types.str;
      description = "The system time zone.";
      default = "Europe/Amsterdam";
    };
    defaultLocale = lib.mkOption {
      type = lib.types.str;
      description = "The default locale for the system.";
      default = "en_US.UTF-8";
    };
    formatting = lib.mkOption {
      type = lib.types.str;
      description = "The locale used for formatting numbers, dates, etc.";
      default = "nl_NL.UTF-8";
    };
    keyboardLayout = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "The keyboard layout settings.";
      default = {
        layout = "us";
        variant = "";
      };
    };
  };

  config = {
    time.timeZone = locale.timeZone;
  } // lib.optionalAttrs isLinux {
    i18n.defaultLocale = locale.defaultLocale;

    i18n.extraLocaleSettings = {
      LC_ADDRESS = locale.formatting;
      LC_IDENTIFICATION = locale.formatting;
      LC_MEASUREMENT = locale.formatting;
      LC_MONETARY = locale.formatting;
      LC_NAME = locale.formatting;
      LC_NUMERIC = locale.formatting;
      LC_PAPER = locale.formatting;
      LC_TELEPHONE = locale.formatting;
      LC_TIME = locale.formatting;
    };

    services.xserver.xkb = locale.keyboardLayout;
  };
}
