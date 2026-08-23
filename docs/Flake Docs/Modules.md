Modules categories are just folders for organization

modules are structured as follows:

```nix
{
  lib,
  config,
  ...
}:
{
  options.CATEGORY.MODULE = {
    enable = lib.mkEnableOption "ENABLE MODULE";
	OPTION = lib.mkOption {
      default = false OR DEFAULT OPTION;
      description = "DESCRIPTION";
      type = lib.types.(bool or int or ints (array) or float or number or str) (see lib.types https://github.com/NixOS/nixpkgs/blob/master/lib/types.nix);
    };
a
  };

  config = lib.mkIf config.CATEGORY.MODULE.enable {
	  "NIX CONFIG and use config.CATEGORY.MODULE.OPTION for the option anywhere"
  };
}
```

With the code above will result in enabling via the following option in the host:
```nix
options = {
	CATEGORY = {
		MODULE.enable = true;
		// or 
		MODULE = {
			enable = true;
			OPTION = X;
		};
	};
};
```