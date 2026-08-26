{
  user,
  hostPlatform,
	lib,
  ...
}:
let
  proxmoxKey = builtins.readFile ./proxmox-vms_rsa.pub;
  breakGlassKey = builtins.readFile ./break-glass-root_ed25519.pub;
in
{
	config = {
		security.sudo.wheelNeedsPassword = false;

		users.users.${user.name} = {
			description = user.fullname;
			home = (if hostPlatform.isLinux then "/home/${user.name}" else "/Users/${user.name}");
			isNormalUser = true;
			extraGroups = [
				"users"
				"networkmanager"
				"wheel"
				"audio"
				"video"
			];
			openssh.authorizedKeys.keys = lib.optional hostPlatform.isServer proxmoxKey;
		};
		# Root: password disabled, key-only via the break-glass key.
		# Private key lives in 1Password — NOT on the macbook. Recovery use only.
		users.users.root.hashedPassword = "!";
		users.users.root.openssh.authorizedKeys.keys = [ breakGlassKey ];
	};
}
