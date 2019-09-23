with import ./lib.nix; with lib;
{ package ? pkgs.jormungandr
, jcli ? pkgs.jormungandr-cli
, genesis-block-hash ? "1f077794039a53309576b35dcd1121375d548db0aeb0b3770a7956cba1a44201"
, color ? true
, rootDir ? "/tmp"
# need to declare other make-config.nix parameters to be able to pass them:
, storage ? "./storage"
, rest_listen ? "127.0.0.1:8443"
, logger_level ? null
, logger_format ? null
, logger_output ? null
, logger_backend ? null
, logs_id ? null
, public_address ? null
, trusted_peers ? "/ip4/3.123.177.192/tcp/3000,/ip4/3.123.155.47/tcp/3000,/ip4/52.57.157.167/tcp/3000,/ip4/3.112.185.217/tcp/3000,/ip4/18.140.134.230/tcp/3000,/ip4/18.139.40.4/tcp/3000,/ip4/3.115.57.216/tcp/3000"
, topics_of_interest ? "messages=high,blocks=high"
}@args:
import ./custom-chain.nix {
  inherit package jcli genesis-block-hash color rootDir storage rest_listen
    logger_level logger_format logger_output logger_backend logs_id
    public_address trusted_peers;
  faucetAmounts = [ 0 ];
}
