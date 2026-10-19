{
  system = "x86_64-linux";
  user = {
    name = "router";
    fullname = "Router";
  };

  type = "server";
  useDefaultHardware = true;
  isHomeServer = true;

  netInterface = {
    ip = "10.0.10.230";
    prefixLength = 24;
  };

  tags = [ "tag:router" ];

  # A disposable copy of the router to try changes on; not managed by Lodestar.
  fleet = false;

  options = {
    homelab.router = {
      enable = true;
      # Let's Encrypt staging (untrusted certificate, browsers warn): a test router
      # must not spend the real wildcard's rate limit.
      acmeStaging = true;
      # Tailscale Service names get this prefix so they don't clash with the router's.
      servicePrefix = "test-";
      # Publish only the echo service on the tailnet.
      tailnetServices = [ "whoami-test" ];
      echo.enable = true;
    };
    # A test Kanidm (modules/identity/) next to the test router, with a staging
    # certificate; the production one is VM 111 (hosts/servers/identity.nix).
    homelab.identity = {
      enable = true;
      domain = "id-test.vanwaaij.com";
      acmeStaging = true;
    };
  };

  config = { ... }: { };
}
