{ package
, jcli
, genesisHash
, trustedPeers
, color
, rootDir ? "./state-jormungandr"
, storage ? "./storage"
, restListen ? "127.0.0.1:3001"
, staking
, stakingFile ? null
, sendLogs
, logConfig ? {}
, listenAddress ? null
, publicAddress ? null
, topicsOfInterest ? null
, pkgs
, lib
, niv
, ...
}@args:
let
  topicsOfInterest' = topicsOfInterest;
  logConfig' = logConfig;
  stakingFile' = stakingFile;
  sanitizedArgs = builtins.removeAttrs args ["color" "pkgs" "niv" "lib"];
in let
  topicsOfInterest = if topicsOfInterest' != null then topicsOfInterest' else {
    messages = if staking then "high" else "low";
    blocks = if staking then "high" else "normal";
  };
  stakingFile = if (stakingFile' != null) then stakingFile' else "./secret.yaml";
  httpHost = "http://${restListen}/api";
  logConfig = {
    level = "info";
    format = "plain";
    output = if sendLogs then "gelf" else "stderr";
    backend = "monitoring.stakepool.cardano-testnet.iohkdev.io:12201";
    id = null;
  } // logConfig';
  configAttrs = {
    inherit storage;
    log = {
      level = logConfig.level;
      format = logConfig.format;
      output = (if (logConfig.output == "gelf") then {
        gelf = {
          backend = logConfig.backend;
          log_id = logConfig.id;
        };
      } else logConfig.output);
    };
    rest = {
      listen = restListen;
    };
    p2p = {
      trusted_peers = trustedPeers;
      topics_of_interest = topicsOfInterest;
    } // lib.optionalAttrs (listenAddress != null) {
      listen_address = listenAddress;
    } // lib.optionalAttrs (publicAddress != null) {
      public_address = publicAddress;
    };
  };
  configAttrsGelf = configAttrs // {
    log = {
      level = logConfig.level;
      format = logConfig.format;
      output = {
        gelf = {
          backend = logConfig.backend;
          log_id = null;
        };
      };
    };
  };
  configFile = builtins.toFile "config.yaml" (builtins.toJSON configAttrs);
  configFileGelf = builtins.toFile "config-gelf.yaml" (builtins.toJSON configAttrsGelf);
  runJormungandr = pkgs.writeScriptBin "run-jormungandr" ''
    #!${pkgs.runtimeShell}

    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli coreutils gnused uuidgen jq curl ])}

    echo "basedir: ${rootDir}"
    mkdir -p ${rootDir}
    cd ${rootDir}

    echo "Starting Jormungandr..."
    jormungandr --genesis-block-hash ${genesisHash} --config ${configFile} ${lib.optionalString staking "--secret ${stakingFile}" }
  '';
  runJormungandrSnappy = pkgs.writeShellScriptBin "run" ''

    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli coreutils gnused uuidgen jq curl ])}

    [ $# -eq 0 ] && { echo "No arguments provided.  Use -h for help."; exit 1; }

    if [[ "''${GELF:-false}" = "true" ]]; then
      OUTPUT="gelf"
    else
      OUTPUT="stderr"
    fi
    STAKING=0
    STAKING_ARGS=""
    PORT=3000
    while getopts 'lsp:h' c
    do
      case "$c" in
        l) OUTPUT="gelf" ;;
        s) STAKING=1 ;;
        p) PORT=$OPTARG ;;
        *)
           echo "usage: $0 [-l] [-s]"
           echo ""
           echo "  -l Send logs to IOHK logs server for diagnostic purposes"
           echo "  -s Enable staking with a secret.yaml (Put file in ${rootDir} or run jormungandr.create-stake-pool)"
           exit 0
           ;;
      esac
    done

    echo "basedir: ${rootDir}"
    mkdir -p ${rootDir}
    cd ${rootDir}
    cp ${configFile} ./config.yaml
    cp ${configFileGelf} ./config-gelf.yaml
    chmod 0644 ./config.yaml ./config-gelf.yaml

    if [ "$OUTPUT" == "gelf" ]; then
      CONFIG_FILE="config-gelf.yaml"
      UUID=$(uuidgen)
      jq '.log.output.gelf.log_id = "'$UUID'"' < config-gelf.yaml > config-gelf-tmp.yaml
      mv config-gelf-tmp.yaml config-gelf.yaml
      echo "log_id: $UUID"
    else
      CONFIG_FILE="config.yaml"
    fi
    if [ $STAKING -eq 1 ]
    then
      echo "Staking enabled!"
      IP=$(curl -s ifconfig.co)
      echo "Announcing my pool as $IP"
      echo "Please ensure port $PORT is forwarded from this IP to this host"
      jq '.p2p.topics_of_interest.messages = "high" | .p2p.topics_of_interest.blocks = "high" |.p2p.topics_of_interest.blocks = "high" | .p2p.listen_address = "/ip4/0.0.0.0/tcp/'$PORT'" | .p2p.public_address = "/ip4/'$IP'/tcp/'$PORT'"' < $CONFIG_FILE > ''${CONFIG_FILE}.tmp
      mv ''${CONFIG_FILE}.tmp $CONFIG_FILE
      if [ -f ./secret.yaml ]
      then
        STAKING_ARGS="--secret ./secret.yaml"
      else
        echo "You must add a secret.yaml file to ${rootDir}/secret.yaml to stake!"
        exit 1
        fi
    fi
    echo "Starting Jormungandr..."
    jormungandr --genesis-block-hash ${genesisHash} --config $CONFIG_FILE $STAKING_ARGS

  '';
  createStakePool = pkgs.writeShellScriptBin "create-stake-pool" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli jq coreutils ])}
    STAKEPOOL_NAME="stake_pool"
    FORCE=0
    while getopts 'fn:h' c
    do
      case "$c" in
        f) FORCE=1 ;;
        n) STAKEPOOL_NAME="$OPTARG";;
        *)
           echo "usage: $0 [-f] [-n <STAKEPOOL_NAME>"
           echo ""
           echo "  -f HERE BE DRAGONS!!! FORCE OVERWRITE EXISTING STAKE POOL. FUNDS MAY BE LOST!!!"
           echo "  -n Name of stake pool to prefix (defaults to stake_pool)"
           exit 0
           ;;
      esac
    done

    if [[ "$FORCE" -eq 0 && -f "${rootDir}/''${STAKEPOOL_NAME}-secret.yaml" ]]
    then
      echo "''${STAKEPOOL_NAME}-secret.yaml exists!"
      echo "Please either specify [-f] flag to overwrite existing stake pool -f [-n <POOLNAME>]."
      exit 1
    elif [[ "$FORCE" -eq 0 && -f "${rootDir}/secret.yaml" ]]
    then
      echo "secret.yaml exists, but you've requested a different pool name."
      echo "Your secret.yaml will be updated to point to newly created pool"
      rm -f "${rootDir}/secret.yaml"
    elif [[ "$FORCE" -eq 0 && -f "${rootDir}/''${STAKEPOOL_NAME}-secret.yaml" ]]
    then
      echo "WARNING! You've specified [-f] flag. Your secrets for previous pool WILL BE REMOVED!"
      rm -f "${rootDir}/''${STAKEPOOL_NAME}-secret.yaml"
      rm -f "${rootDir}/secret.yaml"
    elif [[ "$FORCE" -eq 1 ]]
    then
      rm -f "${rootDir}/''${STAKEPOOL_NAME}-secret.yaml"
      rm -f "${rootDir}/secret.yaml"
    fi

    mkdir -p ${rootDir}
    cd ${rootDir}
    jcli key generate --type=Ed25519 > ''${STAKEPOOL_NAME}_owner_wallet.prv
    jcli key to-public < ''${STAKEPOOL_NAME}_owner_wallet.prv > ''${STAKEPOOL_NAME}_owner_wallet.pub
    jcli address account "$(cat ''${STAKEPOOL_NAME}_owner_wallet.pub)" --testing > ''${STAKEPOOL_NAME}_owner_wallet.address

    jcli key generate --type=SumEd25519_12 > ''${STAKEPOOL_NAME}_kes.prv
    jcli key to-public < ''${STAKEPOOL_NAME}_kes.prv > ''${STAKEPOOL_NAME}_kes.pub
    jcli key generate --type=Curve25519_2HashDH > ''${STAKEPOOL_NAME}_vrf.prv
    jcli key to-public < ''${STAKEPOOL_NAME}_vrf.prv > ''${STAKEPOOL_NAME}_vrf.pub

    jcli certificate new stake-pool-registration \
    --kes-key "$(cat ''${STAKEPOOL_NAME}_kes.pub)" \
    --vrf-key "$(cat ''${STAKEPOOL_NAME}_vrf.pub)" \
    --owner "$(cat ''${STAKEPOOL_NAME}_owner_wallet.pub)" \
    --serial 1010101010 \
    --management-threshold 1 \
    --start-validity 0 > ''${STAKEPOOL_NAME}.cert
    jcli certificate sign ''${STAKEPOOL_NAME}_owner_wallet.prv < ''${STAKEPOOL_NAME}.cert > ''${STAKEPOOL_NAME}.signcert
    jcli certificate get-stake-pool-id < ''${STAKEPOOL_NAME}.signcert > ''${STAKEPOOL_NAME}.id
    NODEID="$(cat ''${STAKEPOOL_NAME}.id)"
    VRFKEY="$(cat ''${STAKEPOOL_NAME}_vrf.prv)"
    KESKEY="$(cat ''${STAKEPOOL_NAME}_kes.prv)"
    jq -n ".genesis.node_id = \"$NODEID\" | .genesis.vrf_key = \"$VRFKEY\" | .genesis.sig_key = \"$KESKEY\"" > ''${STAKEPOOL_NAME}-secret.yaml
    ln -s ''${STAKEPOOL_NAME}-secret.yaml secret.yaml


    echo "Stake pool secrets created and stored in ${rootDir}/secret.yaml"
    echo "The certificate ${rootDir}/stake_pool.signcert needs to be submitted to network using send-certificate"
  '';
  delegateStake = pkgs.writeShellScriptBin "delegate-stake" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli jq coreutils curl gnused gnugrep ])}

    [ $# -eq 0 ] && { echo "No arguments provided.  Use -h for help."; exit 1; }

    while getopts 's:p:h' c
    do
      case "$c" in
        s) SOURCE="$OPTARG" ;;
        p) POOL="$OPTARG" ;;
        *)
           echo "This command creates a stake delegation certificate which can be sent to the blockchain."
           echo
           echo "usage: $0 -s -p [-h]"
           echo
           echo "  -s Path to the private key file of the wallet"
           echo "  -p Stake Pool ID to delegate to"
           exit 0
           ;;
      esac
    done
    if [ -z "''${SOURCE:-}" ]; then
      echo "-s is a required parameter"
      exit 1
    fi
    if [ -z "''${POOL:-}" ]; then
      echo "-p is a required parameter"
      exit 1
    fi
    mkdir -p ${rootDir}
    SOURCE_PK=$(jcli key to-public < "$SOURCE")
    jcli certificate new stake-delegation \
      "$POOL" \
      "$SOURCE_PK" > ${rootDir}/stake_delegation.cert
    jcli certificate sign "$SOURCE" < ${rootDir}/stake_delegation.cert > ${rootDir}/stake_delegation.signcert

    echo "Your delegation certificate is at ${rootDir}/stake_delegation.signcert."
    echo "You need to create a transaction to send the certificate to the blockchain."

  '';
  sendFunds = pkgs.writeShellScriptBin "send-funds" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli jq coreutils curl gnused gnugrep ])}

    [ $# -eq 0 ] && { echo "No arguments provided.  Use -h for help."; exit 1; }

    REST_URL="${httpHost}"
    while getopts 's:d:a:r:h' c
    do
      case "$c" in
        s) SOURCE="$OPTARG" ;;
        d) DEST="$OPTARG" ;;
        a) AMOUNT="$OPTARG" ;;
        r) REST_URL="$OPTARG" ;;
        *)
           echo "This command sends a funds transfer transaction to the blockchain."
           echo "usage: $0 -s -d -a -r [-h]"
           echo ""
           echo "  -s Wallet to send funds from"
           echo "  -d Address to send funds to"
           echo "  -a Amount to send in Lovelace"
           echo "  -r REST endpoint to connect to (defaults to ${httpHost})"
           exit 0
           ;;
      esac
    done
    if [ -z "''${SOURCE:-}" ]; then
      echo "-s is a required parameter"
      exit 1
    fi
    if [ -z "''${DEST:-}" ]; then
      echo "-d is a required parameter"
      exit 1
    fi
    if [ -z "''${AMOUNT:-}" ]; then
      echo "-a is a required parameter"
      exit 1
    fi

    settings=$(curl -s "''${REST_URL}/v0/settings")
    FEE_CONSTANT="$(echo "$settings" | jq -r .fees.constant)"
    FEE_COEFFICIENT="$(echo "$settings" | jq -r .fees.coefficient)"
    BLOCK0_HASH="$(echo "$settings" | jq -r .block0Hash)"
    AMOUNT_WITH_FEES="$((AMOUNT + FEE_CONSTANT + 2 * FEE_COEFFICIENT))"
    TMPDIR="$(mktemp -d)"
    STAGING_FILE="''${TMPDIR}/staging.$$.transaction"
    SOURCE_PK="$(echo "$SOURCE" | jcli key to-public)"
    SOURCE_ADDR="$(jcli address account --testing "$SOURCE_PK")"
    SOURCE_COUNTER="$(jcli rest v0 account get "$SOURCE_ADDR" -h "$REST_URL" | grep '^counter:' | sed -e 's/counter: //' )"

    jcli transaction new --staging "$STAGING_FILE"
    jcli transaction add-account "$SOURCE_ADDR" "$AMOUNT_WITH_FEES" --staging "$STAGING_FILE"
    jcli transaction add-output "$DEST" "$AMOUNT" --staging "$STAGING_FILE"
    jcli transaction finalize --staging "$STAGING_FILE"
    TRANSACTION_ID=$(jcli transaction id --staging "$STAGING_FILE")
    WITNESS_SECRET_FILE="''${TMPDIR}/witness.secret.$$"
    WITNESS_OUTPUT_FILE="''${TMPDIR}/witness.out.$$"

    printf "%s" "$SOURCE" > "$WITNESS_SECRET_FILE"

    echo "The transaction will be posted to the blockchain with genesis hash:"
    echo "  $BLOCK0_HASH"
    jcli transaction make-witness "$TRANSACTION_ID" \
        --genesis-block-hash "$BLOCK0_HASH" \
        --type "account" --account-spending-counter "$SOURCE_COUNTER" \
        "$WITNESS_OUTPUT_FILE" "$WITNESS_SECRET_FILE"
    jcli transaction add-witness "$WITNESS_OUTPUT_FILE" --staging "$STAGING_FILE"

    rm "$WITNESS_SECRET_FILE" "$WITNESS_OUTPUT_FILE"

    # Finalize the transaction and send it
    echo -ne "The id for this funds transfer transaction is:\n  "
    jcli transaction seal --staging "$STAGING_FILE"
    jcli transaction to-message --staging "$STAGING_FILE" | jcli rest v0 message post -h "$REST_URL"

    rm "$STAGING_FILE"
  '';
  sendCertificate = pkgs.writeShellScriptBin "send-certificate" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli jq coreutils curl gnused gnugrep ])}

    [ $# -eq 0 ] && { echo "No arguments provided.  Use -h for help."; exit 1; }

    REST_URL="${httpHost}"
    while getopts 's:c:r:h' c
    do
      case "$c" in
        s) SOURCE="$OPTARG" ;;
        c) CERT="$OPTARG" ;;
        r) REST_URL="$OPTARG" ;;
        *)
           echo "This command sends a certificate to the blockchain."
           echo "usage: $0 -s -c -r [-h]"
           echo ""
           echo "  -s Wallet to send funds from"
           echo "  -c Path to the signed certificate file to send"
           echo "  -r REST endpoint to connect to (defaults to ${httpHost})"
           exit 0
           ;;
      esac
    done
    if [ -z "''${SOURCE:-}" ]; then
      echo "-s is a required parameter"
      exit 1
    fi
    if [ -z "''${CERT:-}" ]; then
      echo "-c is a required parameter"
      exit 1
    fi

    settings=$(curl -s "''${REST_URL}/v0/settings")
    FEE_CONSTANT=$(echo "$settings" | jq -r .fees.constant)
    FEE_COEFFICIENT=$(echo "$settings" | jq -r .fees.coefficient)
    FEE_CERTIFICATE=$(echo "$settings" | jq -r .fees.certificate)
    BLOCK0_HASH=$(echo "$settings" | jq -r .block0Hash)
    AMOUNT_WITH_FEES=$((FEE_CONSTANT + FEE_COEFFICIENT + FEE_CERTIFICATE))
    TMPDIR="$(mktemp -d)"
    STAGING_FILE="''${TMPDIR}/staging.$$.transaction"
    SOURCE_PK=$(echo "$SOURCE" | jcli key to-public)
    SOURCE_ADDR=$(jcli address account --testing "$SOURCE_PK")
    SOURCE_COUNTER=$(jcli rest v0 account get "$SOURCE_ADDR" -h "$REST_URL" | grep '^counter:' | sed -e 's/counter: //' )

    jcli transaction new --staging "$STAGING_FILE"
    jcli transaction add-account "$SOURCE_ADDR" "$AMOUNT_WITH_FEES" --staging "$STAGING_FILE"
    jcli transaction add-certificate --staging "$STAGING_FILE" "$(cat "$CERT")"
    jcli transaction finalize --staging "$STAGING_FILE"
    TRANSACTION_ID=$(jcli transaction id --staging "$STAGING_FILE")
    WITNESS_SECRET_FILE="''${TMPDIR}/witness.secret.$$"
    WITNESS_OUTPUT_FILE="''${TMPDIR}/witness.out.$$"

    printf "%s" "$SOURCE" > "$WITNESS_SECRET_FILE"

    echo "The transaction will be posted to the blockchain with genesis hash:"
    echo "  $BLOCK0_HASH"
    jcli transaction make-witness "$TRANSACTION_ID" \
        --genesis-block-hash "$BLOCK0_HASH" \
        --type "account" --account-spending-counter "$SOURCE_COUNTER" \
        "$WITNESS_OUTPUT_FILE" "$WITNESS_SECRET_FILE"
    jcli transaction add-witness "$WITNESS_OUTPUT_FILE" --staging "$STAGING_FILE"

    rm "$WITNESS_SECRET_FILE" "$WITNESS_OUTPUT_FILE"

    # Finalize the transaction and send it
    echo -ne "The id for this certificate send transaction is:\n  "
    jcli transaction seal --staging "$STAGING_FILE"
    jcli transaction to-message --staging "$STAGING_FILE" | jcli rest v0 message post -h "$REST_URL"

    rm "$STAGING_FILE"
  '';
  checkTxStatus = pkgs.writeShellScriptBin "check-tx-status" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli jq coreutils curl gnused gnugrep ])}

    [ $# -eq 0 ] && { echo "No arguments provided.  Use -h for help."; exit 1; }

    REST_URL="${httpHost}"

    while getopts 't:r:h' c
    do
      case "$c" in
        t) TXID="$OPTARG" ;;
        r) REST_URL="$OPTARG" ;;
        *)
           echo "This command checks status for a specified transaction id."
           echo "usage: $0 -t -r [-h]"
           echo ""
           echo "  -t Transaction ID"
           echo "  -r REST endpoint to connect to (defaults to ${httpHost})"
           exit 0
           ;;
      esac
    done
    if [ -z "''${TXID:-}" ]; then
      echo "-t is a required parameter"
      exit 1
    fi

    jcli rest v0 message logs -h "$REST_URL" --output-format json | jq ".[] | select (.fragment_id == \"$TXID\")"
    '';

  janalyze = let
      python = pkgs.python3.withPackages (ps: with ps; [ requests tabulate ]);
    in pkgs.runCommand "janalyze" {} ''
      mkdir -p $out/bin
      sed "s|env nix-shell$|env ${python}/bin/python|" ${../scripts/janalyze.py} > $out/bin/janalyze
      chmod +x $out/bin/janalyze
    '';

  shells = let
    bootstrap = pkgs.callPackage ./shells/bootstrap.nix args;
    base = pkgs.stdenv.mkDerivation {
      name = "jormungandr-testnet";
      buildInputs = [
        package
        jcli
        createStakePool
        sendFunds
        sendCertificate
        delegateStake
        checkTxStatus
        runJormungandr
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
        echo "To start jormungandr run: \"run-jormungandr\"."
        echo
        export JORMUNGANDR_RESTAPI_URL=${httpHost}
        echo "Using REST API host of ''${JORMUNGANDR_RESTAPI_URL}"
        echo
        echo "To connect using CLI REST:"
        echo "  jcli rest v0 <CMD> "
        echo "For example:"
        echo "  jcli rest v0 node stats get"
        echo
        echo "Available Testnet helper scripts:"
        echo " - send-funds"
        echo " - delegate-stake"
        echo " - send-certificate"
        echo " - check-tx-status"
        echo " - create-stake-pool"
        echo
        echo "Additional shell functions:"
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
  inherit shells runJormungandr runJormungandrSnappy createStakePool sendFunds
          sendCertificate delegateStake janalyze;
}
