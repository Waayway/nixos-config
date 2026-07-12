{
  networking.useDHCP = false;

  networking.interfaces.ens18.ipv4.addresses = [{
    address      = "10.0.10.201";
    prefixLength = 24;
  }];

  networking.defaultGateway = "10.0.10.1";
  networking.nameservers    = [ "10.0.10.1" "1.1.1.1" ];
}
