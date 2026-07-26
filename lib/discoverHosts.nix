{ lib }:
hostsDir:
let
  # Each immediate subdirectory of hostsDir is a category (servers, workstations, ...).
  # Replace with an explicit list if you want to keep non-host dirs out:
  #   categories = [ "servers" "workstations" ];
  categories = lib.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir hostsDir)
  );

  # A host is either `foo.nix` or a directory `foo/` containing default.nix.
  # `dir` is the category directory the entry was read from.
  isHostEntry =
    dir: name: type:
    (type == "regular" && lib.hasSuffix ".nix" name)
    || (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"));

  hostNameOf = name: type: if type == "regular" then lib.removeSuffix ".nix" name else name;

  hostsIn =
    category:
    let
      dir = hostsDir + "/${category}";
      entries = lib.filterAttrs (isHostEntry dir) (builtins.readDir dir);
    in
    lib.mapAttrs' (
      name: type: lib.nameValuePair (hostNameOf name type) (import (dir + "/${name}"))
    ) entries;

  # Host names are flat, so the same name in two categories would otherwise be
  # silently shadowed. Fail at eval time instead.
  merge =
    acc: category:
    let
      new = hostsIn category;
      dupes = lib.intersectLists (lib.attrNames acc) (lib.attrNames new);
    in
    lib.throwIf (dupes != [ ])
      "discoverHosts: duplicate host name(s) ${lib.concatStringsSep ", " dupes} found in ${category}"
      (acc // new);
in
lib.foldl' merge { } categories
