Modules categories are just folders for organization.

Every module is always imported on every host (`modules/system.nix`). Never
leave a module out of the imports per host or platform; the module switches its
own config off:

- Platform: wrap the whole module in `lib.optionalAttrs hostPlatform.isLinux`
  (or `isDarwin`). Not `mkIf`: options that don't exist on the other platform
  error even under `mkIf false`.
- Anything else (host type, an enable option): `config = lib.mkIf <cond> { ... };`.
  Workstation-only modules use `lib.mkIf (!hostPlatform.isServer)`.

```nix
{ lib, hostPlatform, ... }:
lib.optionalAttrs hostPlatform.isLinux {
  config = lib.mkIf (!hostPlatform.isServer) {
    services.printing.enable = true;
  };
}
```

Feature modules with their own switch:

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