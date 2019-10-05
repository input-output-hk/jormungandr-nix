with import ../../lib.nix; with lib;
{ dockerEnv ? false
, package ? pkgs.jormungandr
, jcli ? pkgs.jormungandr-cli
, block0_consensus ? "genesis_praos"
, color ? true
, faucetAmount ? 1000000000
, faucetAmounts ? (map (i: faucetAmount) (lib.range 1 numberOfStakePools))
, numberOfStakePools ? if (block0_consensus == "bft") then 0 else 3
, numberOfLeaders ? if (numberOfStakePools == 0) then 1 else numberOfStakePools
, rootDir ? "./state-jormungandr-bootstrap"
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
, genesis-block-hash ? null
, storage ? "./storage"
, rest_listen ? "127.0.0.1:8443"
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
, ...
}@args:
let

  numberOfFaucets = builtins.length faucetAmounts;

  httpHost = "http://${rest_listen}/api";

  genesisGeneratedArgs = {
    inherit block0_consensus slot_duration linear_fees_constant linear_fees_certificate linear_fees_coefficient;
    consensus_leader_ids = map (i: "LEADER_PK_${toString i}") (range 1 numberOfLeaders);
    initial = [{
      fund = imap1 (i: a: {
        address =  "FAUCET_ADDR_${toString i}";
        value = a;}) faucetAmounts;
      }] ++ concatMap (i: [
      { cert = "STAKE_POOL_CERT_${toString i}"; }
      { cert = "STAKE_DELEGATION_CERT_${toString i}"; }]) (range 1 (numberOfStakePools));
  };
  sanitizedArgs = builtins.removeAttrs args ["color" "pkgs" "niv" "lib"];
  genesisJson = (pkgs.callPackage ../make-genesis.nix (genesisGeneratedArgs // args));

  archiveFileName = "config.zip";

  configGeneratedArgs = {
    inherit topics_of_interest rest_listen storage;
    logs_id = if (logs_id == null) then "LOGS_ID" else logs_id;
  };
  configJson = pkgs.callPackage ../make-config.nix (configGeneratedArgs // args);
  # Used outside of nix so we can override whether to use gelf on command-line
  configJsonGelf = pkgs.callPackage ../make-config.nix (configGeneratedArgs // args // { logger_output = "gelf"; });

  genesisSecretJson = pkgs.callPackage ../make-genesis-secret.nix {
    sigKey = "SIG_KEY";
    vrfKey = "VRF_KEY";
    nodeId = "NODE_ID";
  };

  bftSecretJson = pkgs.callPackage ../make-bft-secret.nix {
    sigKey = "SIG_KEY";
  };

  run-command = { config ? "config.yaml"} : "jormungandr --config ${config} " + (concatMapStrings (i:
      "--secret secrets/secret_pool_${toString i}.yaml "
    ) (range 1 (numberOfStakePools))) + (if (block0_consensus == "bft") then (concatMapStrings (i:
      "--secret secrets/secret_bft_stake_${toString i}.yaml "
    ) (range 1 numberOfFaucets)) else "")+ (concatMapStrings (i:
      "--secret secrets/secret_bft_leader_${toString i}.yaml "
    ) (range 1 (numberOfLeaders))) +
    lib.optionalString (genesis-block-hash == null) "--genesis-block block-0.bin " +
    lib.optionalString (genesis-block-hash != null) "--genesis-block-hash ${genesis-block-hash}";

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
${lib.optionalString (genesis-block-hash == null)''
    echo "* Slot duration: ''${RED}${toString slot_duration}''${WHITE}"''}
    echo "* block-0 hash: ''${BLUE}${if (genesis-block-hash != null) then genesis-block-hash else "`jcli genesis hash --input block-0.bin`"}''${WHITE}"
    echo ""
    echo "########################################################"
    echo ""
    '' + (concatMapStrings (idx: let i = toString idx; n = toString (idx -1); in ''
    echo " Faucet account ${i}: ''${GREEN}`jq -r '.initial[0].fund[${n}].address' < genesis.yaml`''${WHITE}"
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

  gen-config-script-fragment-non-nixos = pkgs.callPackage ../generate-config.nix (args // {
    inherit genesis-block-hash genesisJson configJson configJsonGelf genesisSecretJson bftSecretJson rootDir numberOfStakePools numberOfLeaders block0_consensus numberOfFaucets httpHost color linear_fees_constant linear_fees_certificate linear_fees_coefficient jcli storage;
  });


  docker-images = pkgs.callPackage ../docker-images.nix {
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
  '';

  run-jormungandr-script = with pkgs; writeScriptBin "run-jormungandr" (''
    #!${pkgs.runtimeShell}
    echo "Running ${run-command {}}"
  '' + (if (logger_output == "gelf") then ''
    echo "##############################################################################"
    echo ""
    echo "log_id: `jq -r '.log.output.gelf.log_id' < config.yaml`"
    echo ""
    echo "##############################################################################"
    echo ""
    ''
  else "") + ''
    ${package}/bin/${run-command {}}
  '');

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

      mkdir -p ${rootDir}
      cd ${rootDir}

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
        echo "State is stored in ${rootDir}"
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
      jormungandr-bootstrap
      jq
      send-transaction
    ] ++ lib.optional dockerEnv arionPkgs.arion;
    shellHook = ''
      echo "Jormungandr Demo" '' + (if color then ''\
      | ${pkgs.figlet}/bin/figlet -f banner -c \
      | ${pkgs.lolcat}/bin/lolcat'' else "") + ''

      mkdir -p "${rootDir}"
      cd "${rootDir}"

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
      fi

      ${header}
      source ${jcli}/scripts/jcli-helpers

      echo "To start jormungandr run: \"run-jormungandr\" which expands to:"
      echo " ${run-command {}}"
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
  };

in shell // {
  inherit jormungandr-bootstrap docker-images;
}


