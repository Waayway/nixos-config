{ umport, importCurDir, ... }:
{
  imports =
    importCurDir ./.
    ++ umport {
      paths = [
        ./other
        ./gaming
        ./desktop
        ./terminal
        ./programming
        ./applications
      ];
      recursive = true;
      includeHome = false;
    };
}
