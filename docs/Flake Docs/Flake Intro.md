How is this repo structured:

```md
- ~/.flake (root)
  - docs/ (the folder for documentation)
  - hosts/ (The folder for system specific configs including enabling modules)
    - workstations/ (personal machine such as laptops/desktops)
	- servers/ (Anything that is a server)
	- */ (Anything in subfolders is imported instead of defining specific paths)
  - lib/ (Custom nix functions)
    - discoverHosts.nix 
    - mkDarwin.nix (specific make system for macbooks/macos systems)
	- mkSystem.nix (nixos system specific)
	- mkHome.nix (homeManager maker)
	- mkDeployNode.nix (only for servers to deploy remotely via deploy-rs)
	- umport.nix (!! WANT TO DEPRECATE !!, generic importer for .nix file`s)
  - modules/ (All module specific stuff. everything should always be imported automatically and have the if elses built in to the nix file)
	- base/ (everything needed to setup a base system)
	- servers/ (REFACTOR NEEDED)
	- workstations/ (REFACTOR NEEDED)
  - secrets/ (Secret management with SOPS-nix)
  - template/ (iso templates only proxmox currently)
  - wallpapers/ (my wallpapers)
```