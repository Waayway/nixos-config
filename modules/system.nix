{ umport, ... }:
{
  imports = umport {
    paths = [
      ./common
      ./workstation
      ./server
    ];
    recursive = true;
    includeHome = false;
  };
}
