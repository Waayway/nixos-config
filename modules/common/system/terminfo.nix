{ lib, hostPlatform, ... }:
# Terminfo for every terminal (e.g. xterm-ghostty) for all users, so root shells
# (`sudo -i`) and SSH sessions know the terminal.
lib.optionalAttrs hostPlatform.isLinux {
  environment.enableAllTerminfo = true;
}
