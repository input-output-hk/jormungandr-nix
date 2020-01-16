{ packages
, genesisHash
, trustedPeers
, color
, rootDir ? "./state-jormungandr-${environment}"
, storage ? "./storage"
, restListen ? "127.0.0.1:3001"
, staking
, stakingFile ? null
, sendLogs
, logConfig ? {}
, listenAddress ? null
, publicAddress ? null
, topicsOfInterest ? null
, environment ? "custom"
, pkgs
, lib
, niv
, cardanoWallet
, rewardsLog ? false
, enableWallet ? false
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
    log = [{
      level = logConfig.level;
      format = logConfig.format;
      output = (if (logConfig.output == "gelf") then {
        gelf = {
          backend = logConfig.backend;
          log_id = logConfig.id;
        };
      } else logConfig.output);
    }];
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

    export PATH=${lib.makeBinPath (with pkgs; with packages; [ jormungandr jcli coreutils gnused uuidgen jq curl ])}

    echo "basedir: ${rootDir}"
    mkdir -p ${rootDir}
    cd ${rootDir}

    echo "Starting Jormungandr..."
    ${lib.optionalString rewardsLog "mkdir -p rewards\nexport JORMUNGANDR_REWARD_DUMP_DIRECTORY=./rewards"}
    jormungandr --genesis-block-hash ${genesisHash} --config ${configFile} ${lib.optionalString staking "--secret ${stakingFile}" }
  '';
  runRewardAPI = let
    python = pkgs.python3;
    penv = python.buildEnv.override {
      extraLibs = with python.pkgs; [ flask gunicorn watchdog setuptools requests ];
    };
  in pkgs.writeScriptBin "run-reward-api" ''
    #!${pkgs.runtimeShell}

    set -euo pipefail
    export PYTHONPATH=${penv}/${python.sitePackages}
    export JORMUNGANDR_REWARD_DUMP_DIRECTORY=${rootDir}/rewards
    export JORMUNGANDR_RESTAPI_URL="''${JORMUNGANDR_RESTAPI_URL:-'${httpHost}'}"
    export FLASK_APP="''${FLASK_APP:-${pkgs.callPackage ../reward-api {}}/app.py}"
    PYTHONPATH=${penv}/${python.sitePackages}:${pkgs.callPackage ../reward-api {}} ${pkgs.python3Packages.gunicorn}/bin/gunicorn -w 1 -b 127.0.0.1:5000 wsgi:app
  '';
  runJormungandrSnappy = pkgs.writeShellScriptBin "run" ''

    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; with packages; [ jormungandr jcli coreutils gnused uuidgen jq curl ])}

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

    export PATH=${lib.makeBinPath (with pkgs; with packages; [ jormungandr jcli jq coreutils ])}
    STAKEPOOL_NAME="pool"
    TICKER="POOL"
    STAKEPOOL_DESC="An unidentified stake pool"
    TAX_FIXED=0
    TAX_RATIO="0/1"
    TAX_LIMIT=0
    GENESIS=0
    URL="https://www.example.com"
    OVERWRITE=0
    PRIVATE_KEY_PATH=0
    while getopts 'ogf:n:k:t:r:l:u:h' c
    do
      case "$c" in
        o) OVERWRITE=1 ;;
        g) GENESIS=1 ;;
        n) STAKEPOOL_NAME="$OPTARG";;
        k) PRIVATE_KEY_PATH="$OPTARG";;
        t) TICKER="$OPTARG";;
        f) TAX_FIXED="$OPTARG";;
        r) TAX_RATIO="$OPTARG";;
        l) TAX_LIMIT="$OPTARG";;
        u) URL="$OPTARG";;
        *)
           echo "usage: $0 [-o] [-g] [-n <STAKEPOOL_NAME>] [-t <TICKER_NAME>] [-f <TAX_FIXED>] [-r <TAX_RATE>] [-l <TAX_LIMIT] [-u <URL>]"
           echo ""
           echo "  -o HERE BE DRAGONS!!! FORCE OVERWRITE EXISTING STAKE POOL. FUNDS MAY BE LOST!!!"
           echo "  -g Create registration certificate for genesis block"
           echo "  -n Name of stake pool (defaults to pool)"
           echo "  -t Ticker of stake pool (defaults to POOL, must be 5 alphanumeric chars or less)"
           echo "  -f Fixed Tax for pool (default 0)"
           echo "  -r Tax Rate for pool (default 0/1)"
           echo "  -l Tax Limit for pool (default to not set)"
           echo "  -u Stake Pool URL (default https://www.example.com)"
           exit 0
           ;;
      esac
    done

    if [[ "$OVERWRITE" -eq 0 && -f "${rootDir}/''${TICKER}-secret.yaml" ]]
    then
      echo "''${TICKER}-secret.yaml exists!"
      echo "Please either specify [-f] flag to overwrite existing stake pool -f [-n <POOLNAME>]."
      exit 1
    elif [[ "$OVERWRITE" -eq 0 && -f "${rootDir}/secret.yaml" ]]
    then
      echo "secret.yaml exists, but you've requested a different pool name."
      echo "Your secret.yaml will be updated to point to newly created pool"
      rm -f "${rootDir}/secret.yaml"
    elif [[ "$OVERWRITE" -eq 0 && -f "${rootDir}/''${TICKER}-secret.yaml" ]]
    then
      echo "WARNING! You've specified [-f] flag. Your secrets for previous pool WILL BE REMOVED!"
      rm -f "${rootDir}/''${TICKER}-secret.yaml"
      rm -f "${rootDir}/secret.yaml"
    elif [[ "$OVERWRITE" -eq 1 ]]
    then
      rm -f "${rootDir}/''${TICKER}-secret.yaml"
      rm -f "${rootDir}/secret.yaml"
    fi

    if [[ $TAX_LIMIT -eq 0 ]]
    then
      TAX_LIMIT_STRING=""
    else
      TAX_LIMIT_STRING="--tax-limit $TAX_LIMIT"
    fi

    mkdir -p ${rootDir}
    cd ${rootDir}
    if [[ $PRIVATE_KEY_PATH -eq 0 ]]
    then
      jcli key generate --type=Ed25519 > ''${TICKER}_owner_wallet.prv
    else
      cp "$PRIVATE_KEY_PATH" ''${TICKER}_owner_wallet.prv
    fi
    jcli key to-public < ''${TICKER}_owner_wallet.prv > ''${TICKER}_owner_wallet.pub
    jcli address account "$(cat ''${TICKER}_owner_wallet.pub)" --testing > ''${TICKER}_owner_wallet.address

    jcli key generate --type=SumEd25519_12 > ''${TICKER}_kes.prv
    jcli key to-public < ''${TICKER}_kes.prv > ''${TICKER}_kes.pub
    jcli key generate --type=Curve25519_2HashDH > ''${TICKER}_vrf.prv
    jcli key to-public < ''${TICKER}_vrf.prv > ''${TICKER}_vrf.pub

    jcli certificate new stake-pool-registration \
    --kes-key "$(cat ''${TICKER}_kes.pub)" \
    --vrf-key "$(cat ''${TICKER}_vrf.pub)" \
    --owner "$(cat ''${TICKER}_owner_wallet.pub)" \
    --management-threshold 1 \
    ''${TAX_LIMIT_STRING} \
    --tax-ratio ''${TAX_RATIO} \
    --tax-fixed ''${TAX_FIXED} \
    --start-validity 0 > ''${TICKER}.cert
    if [[ $GENESIS -eq 1 ]]
    then
      jcli certificate sign -k ''${TICKER}_owner_wallet.prv < ''${TICKER}.cert > ''${TICKER}.signcert
    fi
    jcli certificate get-stake-pool-id < ''${TICKER}.cert > ''${TICKER}.id
    NODEID="$(cat ''${TICKER}.id)"
    VRFKEY="$(cat ''${TICKER}_vrf.prv)"
    KESKEY="$(cat ''${TICKER}_kes.prv)"
    OWNER_WALLET_PUB_STR="$(cat ''${TICKER}_owner_wallet.pub)"
    jq -n ".genesis.node_id = \"$NODEID\" | .genesis.vrf_key = \"$VRFKEY\" | .genesis.sig_key = \"$KESKEY\"" > ''${TICKER}-secret.yaml
    ln -s ''${TICKER}-secret.yaml secret.yaml
    jq -n ".owner = \"''${OWNER_WALLET_PUB_STR}\" | .name = \"''${STAKEPOOL_NAME}\" | .ticker = \"''${TICKER}\" | .homepage = \"''${URL}\" | .pledge_address = \"$(cat ''${TICKER}_owner_wallet.address)\"" > "''${OWNER_WALLET_PUB_STR}.json"
    jcli key sign --secret-key "''${TICKER}_owner_wallet.prv" --output "''${OWNER_WALLET_PUB_STR}.sig" "''${OWNER_WALLET_PUB_STR}.json"
    echo "Upload ${rootDir}/''${OWNER_WALLET_PUB_STR}.json and ${rootDir}/''${OWNER_WALLET_PUB_STR}.sig to the stake pool registry"
    echo "Stake pool secrets created and stored in ${rootDir}/secret.yaml"
    if [[ $GENESIS -eq 0 ]]
    then
      echo "The certificate ${rootDir}/''${TICKER}.cert needs to be submitted to network using send-pool-registration"
    else
      echo "The certificate ${rootDir}/''${TICKER}.signcert needs to be added to genesis.yaml"
    fi
  '';
  delegateStake = pkgs.writeShellScriptBin "delegate-stake" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; with packages; [ jormungandr jcli jq coreutils curl gnused gnugrep ])}
    GENESIS=0

    [ $# -eq 0 ] && { echo "No arguments provided.  Use -h for help."; exit 1; }

    while getopts 'gs:p:h' c
    do
      case "$c" in
        g) GENESIS=1 ;;
        s) SOURCE="$OPTARG" ;;
        p) POOL="$OPTARG" ;;
        *)
           echo "This command creates a stake delegation certificate which can be sent to the blockchain."
           echo
           echo "usage: $0 -s -p [-h] [-g]"
           echo
           echo "  -s Path to the private key file of the wallet"
           echo "  -g Generate delegation for genesis file"
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
      "$SOURCE_PK" \
      "$POOL" > ${rootDir}/stake_delegation.cert
    if [[ $GENESIS -eq 1 ]]
    then
      jcli certificate sign -k "$SOURCE" < ${rootDir}/stake_delegation.cert > ${rootDir}/stake_delegation.signcert
    fi

    if [[ $GENESIS -eq 0 ]]
    then
      echo "Your delegation certificate is at ${rootDir}/stake_delegation.cert."
      echo "You need to create a transaction to send the certificate to the blockchain."
    else
      echo "Your delegation certificate at ${rootDir}/stake_delegation.signcert needs to be added to genesis.yaml."
    fi

  '';
  sendFunds = pkgs.writeShellScriptBin "send-funds" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; with packages; [ jormungandr jcli jq coreutils curl gnused gnugrep ])}

    [ $# -eq 0 ] && { echo "No arguments provided.  Use -h for help."; exit 1; }

    JORMUNGANDR_RESTAPI_URL="''${JORMUNGANDR_RESTAPI_URL:-'${httpHost}'}"
    while getopts 's:d:a:r:h' c
    do
      case "$c" in
        s) SOURCE="$OPTARG" ;;
        d) DEST="$OPTARG" ;;
        a) AMOUNT="$OPTARG" ;;
        r) JORMUNGANDR_RESTAPI_URL="$OPTARG" ;;
        *)
           echo "This command sends a funds transfer transaction to the blockchain."
           echo "usage: $0 -s -d -a -r [-h]"
           echo ""
           echo "  -s Path to key of Wallet to send funds from"
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

    settings=$(curl -s "''${JORMUNGANDR_RESTAPI_URL}/v0/settings")
    FEE_CONSTANT="$(echo "$settings" | jq -r .fees.constant)"
    FEE_COEFFICIENT="$(echo "$settings" | jq -r .fees.coefficient)"
    BLOCK0_HASH="$(echo "$settings" | jq -r .block0Hash)"
    AMOUNT_WITH_FEES="$((AMOUNT + FEE_CONSTANT + 2 * FEE_COEFFICIENT))"
    TMPDIR="$(mktemp -d)"
    STAGING_FILE="''${TMPDIR}/staging.$$.transaction"
    SOURCE_PK="$(cat "$SOURCE" | jcli key to-public)"
    SOURCE_ADDR="$(jcli address account --testing "$SOURCE_PK")"
    SOURCE_COUNTER="$(jcli rest v0 account get "$SOURCE_ADDR" -h "$JORMUNGANDR_RESTAPI_URL" | grep '^counter:' | sed -e 's/counter: //' )"

    jcli transaction new --staging "$STAGING_FILE"
    jcli transaction add-account "$SOURCE_ADDR" "$AMOUNT_WITH_FEES" --staging "$STAGING_FILE"
    jcli transaction add-output "$DEST" "$AMOUNT" --staging "$STAGING_FILE"
    jcli transaction finalize --staging "$STAGING_FILE"
    TRANSACTION_ID=$(jcli transaction data-for-witness --staging "$STAGING_FILE")
    WITNESS_SECRET_FILE="''${TMPDIR}/witness.secret.$$"
    WITNESS_OUTPUT_FILE="''${TMPDIR}/witness.out.$$"

    printf "%s" "$(cat $SOURCE)" > "$WITNESS_SECRET_FILE"

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
    jcli transaction to-message --staging "$STAGING_FILE" | jcli rest v0 message post -h "$JORMUNGANDR_RESTAPI_URL"

    rm "$STAGING_FILE"
  '';
  sendPoolRegistration = pkgs.writeShellScriptBin "send-pool-registration" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; with packages; [ jormungandr jcli jq coreutils curl gnused gnugrep ])}

    [ $# -eq 0 ] && { echo "No arguments provided.  Use -h for help."; exit 1; }

    JORMUNGANDR_RESTAPI_URL="''${JORMUNGANDR_RESTAPI_URL:-'${httpHost}'}"
    while getopts 's:c:r:h' c
    do
      case "$c" in
        s) SOURCE="$OPTARG" ;;
        c) CERT="$OPTARG" ;;
        r) JORMUNGANDR_RESTAPI_URL="$OPTARG" ;;
        *)
           echo "This command sends a certificate to the blockchain."
           echo "usage: $0 -s -c -r [-h]"
           echo ""
           echo "  -s Path to key of wallet to send funds from"
           echo "  -c Path to the unsigned certificate file to send"
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

    settings=$(curl -s "''${JORMUNGANDR_RESTAPI_URL}/v0/settings")
    FEE_CONSTANT=$(echo "$settings" | jq -r .fees.constant)
    FEE_COEFFICIENT=$(echo "$settings" | jq -r .fees.coefficient)
    FEE_POOL_REGISTRATION=$(echo "$settings" | jq -r .fees.per_certificate_fees.certificate_pool_registration)
    BLOCK0_HASH=$(echo "$settings" | jq -r .block0Hash)
    AMOUNT_WITH_FEES=$((FEE_CONSTANT + FEE_COEFFICIENT + FEE_POOL_REGISTRATION))
    TMPDIR="$(mktemp -d)"
    STAGING_FILE="''${TMPDIR}/staging.$$.transaction"
    SOURCE_PK=$(echo "$(cat $SOURCE)" | jcli key to-public)
    SOURCE_ADDR=$(jcli address account --testing "$SOURCE_PK")
    SOURCE_COUNTER=$(jcli rest v0 account get "$SOURCE_ADDR" -h "$JORMUNGANDR_RESTAPI_URL" | grep '^counter:' | sed -e 's/counter: //' )

    jcli transaction new --staging "$STAGING_FILE"
    jcli transaction add-account "$SOURCE_ADDR" "$AMOUNT_WITH_FEES" --staging "$STAGING_FILE"
    jcli transaction add-certificate --staging "$STAGING_FILE" "$(cat "$CERT")"
    jcli transaction finalize \
      --fee-constant $FEE_CONSTANT \
      --fee-coefficient $FEE_COEFFICIENT \
      --fee-pool-registration $FEE_POOL_REGISTRATION \
      --staging "$STAGING_FILE"
    TRANSACTION_ID=$(jcli transaction data-for-witness --staging "$STAGING_FILE")
    WITNESS_SECRET_FILE="''${TMPDIR}/witness.secret.$$"
    WITNESS_OUTPUT_FILE="''${TMPDIR}/witness.out.$$"

    printf "%s" "$(cat $SOURCE)" > "$WITNESS_SECRET_FILE"

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
    jcli transaction auth --staging "$STAGING_FILE" -k "$SOURCE"
    jcli transaction to-message --staging "$STAGING_FILE" | jcli rest v0 message post -h "$JORMUNGANDR_RESTAPI_URL"

    rm "$STAGING_FILE"
  '';
  sendDelegation = pkgs.writeShellScriptBin "send-delegation" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; with packages; [ jormungandr jcli jq coreutils curl gnused gnugrep ])}

    [ $# -eq 0 ] && { echo "No arguments provided.  Use -h for help."; exit 1; }

    JORMUNGANDR_RESTAPI_URL="''${JORMUNGANDR_RESTAPI_URL:-'${httpHost}'}"
    while getopts 's:c:r:h' c
    do
      case "$c" in
        s) SOURCE="$OPTARG" ;;
        c) CERT="$OPTARG" ;;
        r) JORMUNGANDR_RESTAPI_URL="$OPTARG" ;;
        *)
           echo "This command sends a certificate to the blockchain."
           echo "usage: $0 -s -c -r [-h]"
           echo ""
           echo "  -s Path to key of wallet to send funds from"
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

    settings=$(curl -s "''${JORMUNGANDR_RESTAPI_URL}/v0/settings")
    FEE_CONSTANT=$(echo "$settings" | jq -r .fees.constant)
    FEE_COEFFICIENT=$(echo "$settings" | jq -r .fees.coefficient)
    FEE_CERTIFICATE_STAKE_DELEGATION=$(echo "$settings" | jq -r .fees.per_certificate_fees.certificate_stake_delegation)
    BLOCK0_HASH=$(echo "$settings" | jq -r .block0Hash)
    AMOUNT_WITH_FEES=$((FEE_CONSTANT + FEE_COEFFICIENT + FEE_CERTIFICATE_STAKE_DELEGATION))
    TMPDIR="$(mktemp -d)"
    STAGING_FILE="''${TMPDIR}/staging.$$.transaction"
    SOURCE_PK=$(echo "$(cat $SOURCE)" | jcli key to-public)
    SOURCE_ADDR=$(jcli address account --testing "$SOURCE_PK")
    SOURCE_COUNTER=$(jcli rest v0 account get "$SOURCE_ADDR" -h "$JORMUNGANDR_RESTAPI_URL" | grep '^counter:' | sed -e 's/counter: //' )

    jcli transaction new --staging "$STAGING_FILE"
    jcli transaction add-account "$SOURCE_ADDR" "$AMOUNT_WITH_FEES" --staging "$STAGING_FILE"
    jcli transaction add-certificate --staging "$STAGING_FILE" "$(cat "$CERT")"
    jcli transaction finalize --staging "$STAGING_FILE"
    TRANSACTION_ID=$(jcli transaction data-for-witness --staging "$STAGING_FILE")
    WITNESS_SECRET_FILE="''${TMPDIR}/witness.secret.$$"
    WITNESS_OUTPUT_FILE="''${TMPDIR}/witness.out.$$"

    printf "%s" "$(cat $SOURCE)" > "$WITNESS_SECRET_FILE"

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
    jcli transaction auth --staging "$STAGING_FILE" -k "$SOURCE"
    jcli transaction to-message --staging "$STAGING_FILE" | jcli rest v0 message post -h "$JORMUNGANDR_RESTAPI_URL"

    rm "$STAGING_FILE"
  '';
  checkTxStatus = pkgs.writeShellScriptBin "check-tx-status" ''
    set -euo pipefail

    export PATH=${lib.makeBinPath (with pkgs; with packages; [ jormungandr jcli jq coreutils curl gnused gnugrep ])}

    [ $# -eq 0 ] && { echo "No arguments provided.  Use -h for help."; exit 1; }

    JORMUNGANDR_RESTAPI_URL="''${JORMUNGANDR_RESTAPI_URL:-'${httpHost}'}"

    while getopts 't:r:h' c
    do
      case "$c" in
        t) TXID="$OPTARG" ;;
        r) JORMUNGANDR_RESTAPI_URL="$OPTARG" ;;
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

    jcli rest v0 message logs -h "$JORMUNGANDR_RESTAPI_URL" --output-format json | jq ".[] | select (.fragment_id == \"$TXID\")"
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
      buildInputs = with packages; [
        jormungandr
        jcli
        createStakePool
        sendPoolRegistration
        sendFunds
        sendDelegation
        delegateStake
        checkTxStatus
        runJormungandr
        janalyze
        niv
        pkgs.figlet
        pkgs.lolcat
        (lib.optional enableWallet cardanoWallet)
        (lib.optional rewardsLog runRewardAPI)
      ];
      shellHook = ''
        echo "Jormungandr Testnet" '' + (if color then ''\
        | figlet -f banner -c \
        | lolcat'' else "") + ''

        source ${packages.jcli}/scripts/jcli-helpers
      '';
    };
    testnet = base.overrideAttrs (oldAttrs: {
      shellHook = oldAttrs.shellHook + ''
        echo "* CLI version: ''${GREEN}${packages.jcli.version}''${WHITE}"
        echo "* NODE version: ''${GREEN}${packages.jormungandr.version}''${WHITE}"
        echo "To start jormungandr run: \"run-jormungandr\"."
        echo
        export JORMUNGANDR_RESTAPI_URL="${httpHost}"
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
        echo " - send-pool-registration"
        echo " - send-delegation"
        echo " - check-tx-status"
        echo " - create-stake-pool"
        echo
        echo "Additional shell functions:"
        echo " - jcli-stake-delegate-new"
        echo " - jcli-generate-account"
        echo " - jcli-generate-account-export-suffix"

        echo "You are currently configured for environment ${environment}"
      '';
    });
    devops = base.overrideAttrs (oldAttrs: {
      buildInputs = oldAttrs.buildInputs ++ [ niv ];
    });
  in { inherit testnet devops bootstrap; };
in {
  inherit shells runJormungandr runJormungandrSnappy createStakePool sendFunds
          sendDelegation delegateStake janalyze checkTxStatus packages sendPoolRegistration;
}
