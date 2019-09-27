{ package
, jcli
, genesisHash
, color
, rootDir ? "/tmp"
, storage ? "./storage"
, restListen ? "127.0.0.1:3001"
, staking
, stakingFile ? null
, sendLogs
, logConfig ? {}
, listenAddress ? null
, publicAddress ? null
, trustedPeers ? [
    "/ip4/3.123.177.192/tcp/3000"
    "/ip4/3.123.155.47/tcp/3000"
    "/ip4/52.57.157.167/tcp/3000"
    "/ip4/3.112.185.217/tcp/3000"
    "/ip4/18.140.134.230/tcp/3000"
    "/ip4/18.139.40.4/tcp/3000"
    "/ip4/3.115.57.216/tcp/3000"
  ]
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
  stakingFile = if stakingFile' then stakingFile' else "./secret.yaml";
  httpHost = "http://${restListen}/api";
  logConfig = {
    level = "info";
    format = "plain";
    output = if sendLogs then "gelf" else "stderr";
    backend = "monitoring.stakepool.cardano-testnet.iohkdev.io:12201";
    id = null;
  } // logConfig';
  baseDirName = "jormungandr-" + (builtins.hashString "md5" (builtins.toJSON sanitizedArgs));
  baseDir = rootDir + "/" + baseDirName;
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

    echo "basedir: ${baseDir}"
    mkdir -p ${baseDir}
    cd ${baseDir}

    echo "Starting Jormungandr..."
    jormungandr --genesis-block-hash ${genesisHash} --config ${configFile} ${lib.optionalString staking "--secret ${stakingFile}" }
  '';
  runJormungandrSnappy = pkgs.writeShellScriptBin "run" ''

    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli coreutils gnused uuidgen jq curl ])}

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
      case $c in
        l) OUTPUT="gelf" ;;
        s) STAKING=1 ;;
        p) PORT=$OPTARG ;;
        h)
           echo "usage: $0 [-l]"
           echo ""
           echo "  -l Send logs to IOHK logs server for diagnostic purposes"
           exit 0
           ;;
      esac
    done

    echo "basedir: ${baseDir}"
    mkdir -p ${baseDir}
    cd ${baseDir}
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
        echo "You must add a secret.yaml file to ${baseDir}/secret.yaml to stake!"
        exit 1
        fi
    fi
    echo "Starting Jormungandr..."
    jormungandr --genesis-block-hash ${genesisHash} --config $CONFIG_FILE $STAKING_ARGS

  '';
  createStakePool = pkgs.writeShellScriptBin "create-stake-pool" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli jq coreutils ])}
    mkdir -p ${baseDir}
    cd ${baseDir}
    jcli key generate --type=Ed25519 > stake_pool_owner_wallet.prv
    cat stake_pool_owner_wallet.prv | jcli key to-public > stake_pool_owner_wallet.pub
    jcli address account $(cat stake_pool_owner_wallet.pub) --testing > stake_pool_owner_wallet.address


    jcli key generate --type=SumEd25519_12 > stake_pool_kes.prv
    cat stake_pool_kes.prv | jcli key to-public > stake_pool_kes.pub
    jcli key generate --type=Curve25519_2HashDH > stake_pool_vrf.prv
    cat stake_pool_vrf.prv | jcli key to-public > stake_pool_vrf.pub

    jcli certificate new stake-pool-registration \
    --kes-key $(cat stake_pool_kes.pub) \
    --vrf-key $(cat stake_pool_vrf.pub) \
    --owner $(cat stake_pool_owner_wallet.pub) \
    --serial 1010101010 \
    --management-threshold 1 \
    --start-validity 0 > stake_pool.cert
    cat stake_pool.cert | jcli certificate sign stake_pool_owner_wallet.prv > stake_pool.signcert
    cat stake_pool.signcert | jcli certificate get-stake-pool-id > stake_pool.id
    jq -n '.genesis.node_id = "'$(cat stake_pool.id)'" | .genesis.vrf_key = "'$(cat stake_pool_vrf.prv)'" | .genesis.sig_key = "'$(cat stake_pool_kes.prv)'"' > secret.yaml


    echo "Stake pool secrets created and stored in ${baseDir}/secret.yaml"
  '';
  delegateStake = pkgs.writeShellScriptBin "delegate-stake" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli jq coreutils curl gnused gnugrep ])}
    REST_URL=${httpHost}

    while getopts 's:p:r:h' c
    do
      case $c in
        s) SOURCE=$OPTARG ;;
        p) POOL=$OPTARG ;;
        r) REST_URL=$OPTARG ;;
        h)
           echo "usage: $0 -s -d -a [-h]"
           echo ""
           echo "  -s Path to private key of wallet"
           echo "  -p Stake Pool ID to delegate to"
           echo "  -r REST endpoint to connect to (defaults to ${httpHost})"
           exit 0
           ;;
      esac
    done
    if [ -z "$SOURCE" ]
    then
      echo "-s is a required parameter"
      exit 1
    fi
    if [ -z "$POOL" ]
    then
      echo "-p is a required parameter"
      exit 1
    fi
    mkdir -p ${baseDir}
    SOURCE_PK=$(cat $SOURCE | jcli key to-public)
    jcli certificate new stake-delegation \
        ''${POOL} \
        $SOURCE_PK > ${baseDir}/stake_delegation.cert
    cat ${baseDir}/stake_delegation.cert | jcli certificate sign ''${SOURCE} > ${baseDir}/stake_delegation.signcert

    echo "Your delegation certificate is at ${baseDir}/stake_delegation.signcert"
    echo "You need to create a transaction to send the certificate to the blockchain"

  '';
  sendFunds = pkgs.writeShellScriptBin "send-funds" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli jq coreutils curl gnused gnugrep ])}
    REST_URL=${httpHost}
    while getopts 's:d:a:r:h' c
    do
      case $c in
        s) SOURCE=$OPTARG ;;
        d) DEST=$OPTARG ;;
        a) AMOUNT=$OPTARG ;;
        r) REST_URL=$OPTARG ;;
        h)
           echo "usage: $0 -s -d -a [-h]"
           echo ""
           echo "  -s Wallet to send funds from"
           echo "  -d Address to send funds to"
           echo "  -a Amount to send"
           echo "  -r REST endpoint to connect to (defaults to ${httpHost})"
           exit 0
           ;;
      esac
    done
    if [ -z "$SOURCE" ]
    then
      echo "-s is a required parameter"
      exit 1
    fi
    if [ -z "$DEST" ]
    then
      echo "-d is a required parameter"
      exit 1
    fi
    if [ -z "$AMOUNT" ]
    then
      echo "-a is a required parameter"
      exit 1
    fi

    settings="$(curl -s ''${REST_URL}/v0/settings)"
    FEE_CONSTANT=$(echo $settings | jq -r .fees.constant)
    FEE_COEFFICIENT=$(echo $settings | jq -r .fees.coefficient)
    FEE_CERTIFICATE=$(echo $settings | jq -r .fees.certificate)
    BLOCK0_HASH=$(echo $settings | jq -r .block0Hash)
    AMOUNT_WITH_FEES=$((''${AMOUNT} + ''${FEE_CONSTANT} + 2 * ''${FEE_COEFFICIENT}))
    TMPDIR=$(mktemp -d)
    STAGING_FILE="''${TMPDIR}/staging.''$$.transaction"
    SOURCE_PK=$(echo ''${SOURCE} | jcli key to-public)
    SOURCE_ADDR=$(jcli address account --testing ''${SOURCE_PK})
    SOURCE_COUNTER=$(jcli rest v0 account get "''${SOURCE_ADDR}" -h "''${REST_URL}" | grep '^counter:' | sed -e 's/counter: //' )

    jcli transaction new --staging ''${STAGING_FILE}
    jcli transaction add-account "''${SOURCE_ADDR}" "''${AMOUNT_WITH_FEES}" --staging "''${STAGING_FILE}"
    jcli transaction add-output "''${DEST}" "''${AMOUNT}" --staging "''${STAGING_FILE}"
    jcli transaction finalize --staging ''${STAGING_FILE}
    TRANSACTION_ID=$(jcli transaction id --staging ''${STAGING_FILE})
    WITNESS_SECRET_FILE="''${TMPDIR}/witness.secret.''$$"
    WITNESS_OUTPUT_FILE="''${TMPDIR}/witness.out.''$$"

    printf "''${SOURCE}" > ''${WITNESS_SECRET_FILE}

    echo $BLOCK0_HASH
    jcli transaction make-witness ''${TRANSACTION_ID} \
        --genesis-block-hash ''${BLOCK0_HASH} \
        --type "account" --account-spending-counter "''${SOURCE_COUNTER}" \
        ''${WITNESS_OUTPUT_FILE} ''${WITNESS_SECRET_FILE}
    jcli transaction add-witness ''${WITNESS_OUTPUT_FILE} --staging "''${STAGING_FILE}"

    rm ''${WITNESS_SECRET_FILE} ''${WITNESS_OUTPUT_FILE}

    # Finalize the transaction and send it
    jcli transaction seal --staging "''${STAGING_FILE}"
    jcli transaction to-message --staging "''${STAGING_FILE}" | jcli rest v0 message post -h "''${REST_URL}"

    rm ''${STAGING_FILE}
  '';
  sendCertificate = pkgs.writeShellScriptBin "send-certificate" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli jq coreutils curl gnused gnugrep ])}
    REST_URL=${httpHost}
    while getopts 's:c:r:h' c
    do
      case $c in
        s) SOURCE=$OPTARG ;;
        c) CERT=$OPTARG ;;
        r) REST_URL=$OPTARG ;;
        h)
           echo "usage: $0 -s -c -r [-h]"
           echo ""
           echo "  -s Wallet to send funds from"
           echo "  -c Signed certificate to send"
           echo "  -r REST endpoint to connect to (defaults to ${httpHost})"
           exit 0
           ;;
      esac
    done
    if [ -z "$SOURCE" ]
    then
      echo "-s is a required parameter"
      exit 1
    fi
    if [ -z "$CERT" ]
    then
      echo "-c is a required parameter"
      exit 1
    fi

    settings="$(curl -s ''${REST_URL}/v0/settings)"
    FEE_CONSTANT=$(echo $settings | jq -r .fees.constant)
    FEE_COEFFICIENT=$(echo $settings | jq -r .fees.coefficient)
    FEE_CERTIFICATE=$(echo $settings | jq -r .fees.certificate)
    BLOCK0_HASH=$(echo $settings | jq -r .block0Hash)
    AMOUNT_WITH_FEES=$((''${FEE_CONSTANT} + ''${FEE_COEFFICIENT} + ''${FEE_CERTIFICATE}))
    TMPDIR=$(mktemp -d)
    STAGING_FILE="''${TMPDIR}/staging.''$$.transaction"
    SOURCE_PK=$(echo ''${SOURCE} | jcli key to-public)
    SOURCE_ADDR=$(jcli address account --testing ''${SOURCE_PK})
    SOURCE_COUNTER=$(jcli rest v0 account get "''${SOURCE_ADDR}" -h "''${REST_URL}" | grep '^counter:' | sed -e 's/counter: //' )

    jcli transaction new --staging ''${STAGING_FILE}
    jcli transaction add-account "''${SOURCE_ADDR}" "''${AMOUNT_WITH_FEES}" --staging "''${STAGING_FILE}"
    jcli transaction add-certificate --staging ''${STAGING_FILE} ''$(cat ''${CERT})
    jcli transaction finalize --staging ''${STAGING_FILE}
    TRANSACTION_ID=$(jcli transaction id --staging ''${STAGING_FILE})
    WITNESS_SECRET_FILE="''${TMPDIR}/witness.secret.''$$"
    WITNESS_OUTPUT_FILE="''${TMPDIR}/witness.out.''$$"

    printf "''${SOURCE}" > ''${WITNESS_SECRET_FILE}

    echo $BLOCK0_HASH
    jcli transaction make-witness ''${TRANSACTION_ID} \
        --genesis-block-hash ''${BLOCK0_HASH} \
        --type "account" --account-spending-counter "''${SOURCE_COUNTER}" \
        ''${WITNESS_OUTPUT_FILE} ''${WITNESS_SECRET_FILE}
    jcli transaction add-witness ''${WITNESS_OUTPUT_FILE} --staging "''${STAGING_FILE}"

    rm ''${WITNESS_SECRET_FILE} ''${WITNESS_OUTPUT_FILE}

    # Finalize the transaction and send it
    jcli transaction seal --staging "''${STAGING_FILE}"
    jcli transaction to-message --staging "''${STAGING_FILE}" | jcli rest v0 message post -h "''${REST_URL}"

    rm ''${STAGING_FILE}
  '';
  checkTxStatus = pkgs.writeShellScriptBin "check-tx-status" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; [ package jcli jq coreutils curl gnused gnugrep ])}
    REST_URL=${httpHost}

    while getopts 't:r:h' c
    do
      case $c in
        t) TXID=$OPTARG ;;
        r) REST_URL=$OPTARG ;;
        h)
           echo "usage: $0 -s -d -a [-h]"
           echo ""
           echo "  -t Transaction ID"
           echo "  -r REST endpoint to connect to (defaults to ${httpHost})"
           exit 0
           ;;
      esac
    done
    jcli rest v0 message logs -h "''${REST_URL}" --output-format json | jq '.[] | select (.fragment_id == "'$TXID'")'
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
  inherit shells runJormungandr runJormungandrSnappy createStakePool sendFunds sendCertificate delegateStake;
}
