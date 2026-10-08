{
  config,
  lib,
  hostPlatform,
  ...
}:
let
  cfg = config.darwin.finderSidebar;
in
{
  options.darwin.finderSidebar = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [
      "Documents"
      "code"
    ];
    description = ''
      Folders (relative to $HOME) to add to Finder's sidebar Favorites.
      Missing folders are skipped and picked up on a later switch; existing
      favorites are never removed or reordered. Needs the Xcode command line
      tools (runs finder-sidebar.swift with /usr/bin/swift).
    '';
  };

  config = lib.optionalAttrs hostPlatform.isDarwin {
    home.activation.finderSidebar = lib.mkIf (cfg != [ ]) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if /usr/bin/xcode-select -p >/dev/null 2>&1; then
          run /usr/bin/swift ${./finder-sidebar.swift} \
            ${lib.escapeShellArgs (map (p: "${config.home.homeDirectory}/${p}") cfg)} \
            2>/dev/null || true
        else
          echo "finderSidebar: Xcode command line tools missing, skipping" >&2
        fi
      ''
    );
  };
}
