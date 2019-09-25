let
  commonLib = import ./lib.nix;
  in with commonLib.lib; with import ./lib.nix;
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
let
  niv = (import sources.niv {}).niv;
  httpHost = "http://${rest_listen}/api";
  shells = let
    bootstrap = import ./custom-chain.nix (removeAttrs args ["trusted_peers"]);
    base = pkgs.stdenv.mkDerivation {
      name = "jormungandr-testnet";
      buildInputs = [
        package
        jcli
      ];
      shellHook = ''
        echo "Jormungandr Testnet" '' + (if color then ''\
        | ${pkgs.figlet}/bin/figlet -f banner -c \
        | ${pkgs.lolcat}/bin/lolcat'' else "") + ''

        source ${jcli}/scripts/jcli-helpers
      '';
    };
    testnet = base.overrideAttrs (oldAttrs: {
      shellHook = oldAttrs.shellHook + ''
        echo "To start jormungandr run: \"run-jormungandr\" which expands to:"
        echo ""
        echo "To connect using CLI REST:"
        echo "  jcli rest v0 <CMD> --host \"${httpHost}\""
        echo "For example:"
        echo "  jcli rest v0 node stats get -h \"${httpHost}\""
        echo ""
        echo "Available helper scripts:"
        echo " - send-transaction"
        echo " - ./create-account-and-delegate.sh"
        echo " - ./faucet-send-certificate.sh"
        echo " - ./faucet-send-money.sh"
        echo " - jcli-stake-delegate-new"
        echo " - jcli-generate-account"
        echo " - jcli-generate-account-export-suffix"
      '';
    });
    devops = base.overrideAttrs (oldAttrs: {
      buildInputs = oldAttrs.buildInputs ++ [ niv ];
    });
  in { inherit testnet devops bootstrap; };
in {
  inherit shells niv sources;
}
