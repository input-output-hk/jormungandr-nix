with import ./lib.nix; with lib;
{ dockerEnv ? false
, package ? pkgs.jormungandr
, jcli ? pkgs.jormungandr-cli
, cardano-wallet ? pkgs.cardano-wallet-jormungandr
, block0_consensus ? "genesis_praos"
, color ? true
, faucetAmounts ? [ 1000000000 1000000000 1000000000 ]
, numberOfStakePools ? if (block0_consensus == "bft") then 1 else (builtins.length faucetAmounts)
, numberOfLeaders ? 1
, rootDir ? "/tmp"
# need to declare other make-genesis.nix parameters to be able to pass them:
, block0_date ? null
, isProduction ? null
, slots_per_epoch ? null
, slot_duration ? 10
, epoch_stability_depth ? null
, bft_slots_ratio ? null
, consensus_genesis_praos_active_slot_coeff ? null
, max_number_of_transactions_per_block ? null
, linear_fees_constant ? 10
, linear_fees_coefficient ? 0
, linear_fees_certificate ? 0
, kes_update_speed ? null
# Same for make-config.nix
, storage ? "./storage"
, rest_listen ? "127.0.0.1:8443"
, rest_prefix ? "api"
, logger_level ? null
, logger_format ? null
, logger_output ? null
, logger_backend ? null
, logs_id ? null
, public_address ? null
, trusted_peers ? null
, topics_of_interest ? if (numberOfStakePools > 0)
    then "messages=high,blocks=high"
    else "messages=low,blocks=normal"
}@args:
let

  numberOfFaucets = builtins.length faucetAmounts;

  httpPort = builtins.elemAt (builtins.split ":" rest_listen) 2;

  httpHost = "http://${rest_listen}/${rest_prefix}";

  genesisGeneratedArgs = {
    inherit block0_consensus slot_duration linear_fees_constant linear_fees_certificate linear_fees_coefficient;
    consensus_leader_ids = map (i: "LEADER_PK_${toString i}") (range 1 numberOfLeaders);
    initial = imap1 (i: a: { fund = [{
        address =  "FAUCET_ADDR_${toString i}";
        value = a;
      }];}) faucetAmounts
      ++ builtins.fromJSON (builtins.readFile ./static-test-funds.json)
      ++ concatMap (i: [
        { cert = "STAKE_POOL_CERT_${toString i}"; }
        { cert = "STAKE_DELEGATION_CERT_${toString i}"; }]) (range 1 (numberOfStakePools));
  };
  genesisJson = (pkgs.callPackage ./nix/make-genesis.nix (genesisGeneratedArgs // args));

  baseDirName = "jormungandr-" + (builtins.hashString "md5" (builtins.toJSON (builtins.removeAttrs args ["color" "dockerEnv"])));
  baseDir = rootDir + "/" + baseDirName;
  archiveFileName = baseDirName + "-config.zip";

  configGeneratedArgs = {
    inherit topics_of_interest rest_listen rest_prefix storage;
    logs_id = if (logs_id == null) then "LOGS_ID" else logs_id;
  };
  configJson = pkgs.callPackage ./nix/make-config.nix (configGeneratedArgs // args);
  # Used outside of nix so we can override whether to use gelf on command-line
  configJsonGelf = pkgs.callPackage ./nix/make-config.nix (configGeneratedArgs // args // { logger_output = "gelf"; });

  genesisSecretJson = pkgs.callPackage ./nix/make-genesis-secret.nix {
    sigKey = "SIG_KEY";
    vrfKey = "VRF_KEY";
    nodeId = "NODE_ID";
  };

  bftSecretJson = pkgs.callPackage ./nix/make-bft-secret.nix {
    sigKey = "SIG_KEY";
  };

  run-command = { config ? "config.yaml"} : "jormungandr --genesis-block block-0.bin --config ${config} " + (concatMapStrings (i:
      "--secret secrets/secret_pool_${toString i}.yaml "
    ) (range 1 (numberOfStakePools))) + (if (block0_consensus == "bft") then (concatMapStrings (i:
      "--secret secrets/secret_bft_stake_${toString i}.yaml "
    ) (range 1 numberOfFaucets)) else "") + (concatMapStrings (i:
      "--secret secrets/secret_bft_leader_${toString i}.yaml "
    ) (range 1 (numberOfLeaders)))
    + "--secret ${./static-bft-leader-secret.yaml}";

  header = with builtins; (if color then ''\
    GREEN=`printf "\033[0;32m"`
    RED=`printf "\033[0;31m"`
    BLUE=`printf "\033[0;33m"`
    WHITE=`printf "\033[0m"`
    '' else ''
    GREEN=""
    RED=""
    BLUE=""
    WHITE=""
    '') + ''
    echo "##############################################################################"
    echo ""
    echo "* CLI version: ''${GREEN}${jcli.version}''${WHITE}"
    echo "* NODE version: ''${GREEN}${package.version}''${WHITE}"
    echo ""
    echo "########################################################"
    echo ""
    echo "* Consensus: ''${RED}${block0_consensus}''${WHITE}"
    echo "* REST Port: ''${RED}${rest_listen}''${WHITE}"
    echo "* Slot duration: ''${RED}${toString slot_duration}''${WHITE}"
    echo "* block-0 hash: ''${BLUE}`jcli genesis hash --input block-0.bin`''${WHITE}"
    echo ""
    echo "########################################################"
    echo ""
    '' + (concatMapStrings (idx: let i = toString idx; n = toString (idx -1); in ''
    echo " Faucet account ${i}: ''${GREEN}`jq -r '.initial[${n}].fund[0].address' < genesis.yaml`''${WHITE}"
    echo "  * public:  ''${BLUE}`cat stake_${i}_key.pk`''${WHITE}"
    echo "  * secret:  ''${RED}`cat secrets/stake_${i}_key.sk`''${WHITE}"
    echo "  * amount:  ''${GREEN}${toString (elemAt faucetAmounts (idx -1))}''${WHITE}"
    '' + (if idx <= numberOfStakePools then ''
    echo "  * pool id: ''${GREEN}`cat secrets/secret_pool_${i}.yaml | jq -r '.genesis.node_id'`''${WHITE}"
    '' else "") + ''
    echo ""
    '') (range 1 numberOfFaucets)) + ''
    echo "##############################################################################"
    echo ""
  '';

  gen-config-script-fragment-non-nixos = pkgs.callPackage ./nix/generate-config.nix (args // {
    inherit genesisJson configJson configJsonGelf genesisSecretJson bftSecretJson baseDir numberOfStakePools numberOfLeaders block0_consensus numberOfFaucets httpHost color linear_fees_constant linear_fees_certificate linear_fees_coefficient jcli storage;
  });


  docker-images = pkgs.callPackage ./nix/docker-images.nix {
    jormungandr-bootstrap = (import ./. {
      storage = "/data/storage";
    }).jormungandr-bootstrap;
  };

  gen-config-script = with pkgs; writeScriptBin "generate-config" ''
    #!${pkgs.runtimeShell}

    set -euo pipefail

    export PATH=${lib.makeBinPath [ jcli package remarshal zip uuidgen ]}:$PATH
    ${gen-config-script-fragment-non-nixos}

    if [ -f "${archiveFileName}" ]; then
      mv "${archiveFileName}" "${archiveFileName}.bak"
    fi
    zip -q -r "${archiveFileName}" block-0.bin config.yaml genesis.yaml secrets *cert

    ${header}
  '';

  run-jormungandr-script = with pkgs; writeScriptBin "run-jormungandr" (''
    #!${pkgs.runtimeShell}
    echo "Running ${run-command {}} $@"
  '' + (if (logger_output == "gelf") then ''
    echo "##############################################################################"
    echo ""
    echo "log_id: `jq -r '.log.output.gelf.log_id' < config.yaml`"
    echo ""
    echo "##############################################################################"
    echo ""
    ''
  else "") + ''
    exec ${package}/bin/${run-command {}} $@
  '');

  cardano-wallet-serve-script = with pkgs; writeScriptBin "cardano-wallet-serve" ''
    #!${pkgs.runtimeShell}
    GENESIS_HASH=`jcli genesis hash --input block-0.bin`
    exec cardano-wallet-jormungandr serve --node-port ${httpPort} --genesis-hash $GENESIS_HASH --database ./wallet.db $@
  '';

  run-jormungandr-and-cardano-wallet-script = with pkgs; writeScriptBin "run-jormungandr-and-cardano-wallet" ''
    #!${pkgs.runtimeShell}
    exec ${pkgs.parallel}/bin/parallel --line-buffer ::: run-jormungandr cardano-wallet-serve
  '';

  display-test-wallets-mnemonics-script = with pkgs; writeScriptBin "display-test-wallets-mnemonics" ''
    #!${pkgs.runtimeShell}
    cat --number ${./static-test-funds-mnemonics.txt}
  '';

  jormungandr-bootstrap = with pkgs; writeScriptBin "bootstrap" (''
    #!${pkgs.runtimeShell}

    set -euo pipefail

    export PATH=${makeBinPath [ package jcli coreutils gnused uuidgen jq ]}

    if [[ "''${GELF:-false}" = "true" ]]; then
      OUTPUT="gelf"
    else
      OUTPUT="stderr"
    fi
    AUTOSTART=0
    while getopts 'la' c
    do
        case $c in
            a) AUTOSTART=1 ;;
            l) OUTPUT="gelf" ;;
            h)
                echo "usage: $0 [-a] [-l]"
                echo ""
                echo "  -a Auto-start jormungandr after generating config"
                echo "  -l Send logs to IOHK logs server for diagnostic purposes"
                exit 0
                ;;
        esac
      done

      mkdir -p ${baseDir}
      cd ${baseDir}

      rm -f config.yaml
      ${gen-config-script-fragment-non-nixos}

      ${header}

      if [ "$OUTPUT" == "gelf" ]; then
         CONFIG_FILE="config-gelf.yaml"
         echo "log_id: `jq -r '.log.output.gelf.log_id' < config-gelf.yaml`"
      else
         CONFIG_FILE="config.yaml"
      fi
      STARTCMD="${run-command { config = "$CONFIG_FILE"; }}"

      if [ "$AUTOSTART" == "1" ]; then
        echo "Running"
        echo " $STARTCMD"
        echo "State is stored in ${baseDir}"
        echo ""
        $STARTCMD
      else
        echo "To start jormungandr run:"
        echo " $STARTCMD"
      fi

  '');

  send-transaction = pkgs.writeScriptBin "send-transaction" (
    builtins.replaceStrings ["http://127.0.0.1:8443/api"] [httpHost]
    (builtins.readFile (jcli + "/scripts/send-transaction"))
  );

  shell = pkgs.stdenv.mkDerivation {
    name = "jormungandr-demo";

    buildInputs = with pkgs; [
      package
      jcli
      gen-config-script
      run-jormungandr-script
      cardano-wallet-serve-script
      run-jormungandr-and-cardano-wallet-script
      jormungandr-bootstrap
      jq
      send-transaction
      cardano-wallet
      display-test-wallets-mnemonics-script
    ] ++ lib.optional dockerEnv arionPkgs.arion;
    shellHook = ''
      echo "Jormungandr Demo" '' + (if color then ''\
      | ${pkgs.figlet}/bin/figlet -f banner -c \
      | ${pkgs.lolcat}/bin/lolcat'' else "") + ''

      mkdir -p "${baseDir}"
      cd "${baseDir}"

      '' + (if dockerEnv then ''
      mkdir -p docker
      if [ -L nixos ]; then
        rm nixos
      fi
      ln -sf "${./.}/nixos" nixos
      ln -sf "${./.}/docker/arion-pkgs.nix" docker/arion-pkgs.nix
      if [ ! -f ./docker/arion-compose.nix ]; then
        cp "${./.}/docker/arion-compose.nix" docker/
      fi
      '' else "") + ''
      if [ ! -f config.yaml ]; then
        generate-config
      else
        ${header}
      fi

      source ${jcli}/scripts/jcli-helpers

      echo "To start jormungandr run: \"run-jormungandr\" which expands to:"
      echo " ${run-command {}}"
      echo ""
      echo "To serve the cardano-wallet api on top of a running jormungandr, run: \"cardano-wallet-serve\""
      echo ""
      echo "To run both jormungandr and cardano-wallet api at once, run: \"run-jormungandr-and-cardano-wallet\""
      echo ""
      echo "To connect directly to jormungandr using CLI REST:"
      echo "  jcli rest v0 <CMD> --host \"${httpHost}\""
      echo "For example:"
      echo "  jcli rest v0 node stats get -h \"${httpHost}\""
      echo ""
      echo "To use cardano wallet api (need \"nix-shell --argstr block0_consensus bft\") see:"
      echo "  cardano-wallet-jormungandr --help"
      echo "(and \"display-test-wallets-mnemonics\" to restore an exising wallet from its mnemonics passphrase)"
      echo ""
      echo "Available helper scripts:"
      echo " - send-transaction"
      echo " - ./create-account-and-delegate.sh"
      echo " - ./faucet-send-certificate.sh"
      echo " - ./faucet-send-money.sh"
      echo " - jcli-stake-delegate-new"
      echo " - jcli-generate-account"
      echo " - jcli-generate-account-export-suffix"
      echo " - jcli-generate-account-export-suffix"
    '';
  };

in shell // {
  inherit jormungandr-bootstrap docker-images;
}


