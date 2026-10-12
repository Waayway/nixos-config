{ lib }:
hosts:
let
  isFleet = h: h.fleet or false;
  defaultChannel = h: if h.category == "servers" then "stable" else "unstable";
in
lib.mapAttrsToList (name: h: {
  inherit name;
  inherit (h) system;
  user = h.user.name;
  channel = h.channel or (defaultChannel h);
  os = if lib.hasSuffix "darwin" h.system then "darwin" else "linux";
}) (lib.filterAttrs (_: isFleet) hosts)
