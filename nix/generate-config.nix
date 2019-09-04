{ stdenv
, lib
, jcli
, storage
, writeScriptBin
, block0_consensus
, isProduction ? false
, addrTypeFlag ? if (isProduction) then "" else "--testing"
, numberOfFaucets
, numberOfStakePools
, numberOfLeaders
, configJson
, configJsonGelf
, genesisJson
, genesisSecretJson
, bftSecretJson
, httpHost
, color
, linear_fees_constant
, linear_fees_certificate
, linear_fees_coefficient
, ...
}:
with lib; ''
  CONFIG_JSON=$(cat <<'EOF'
    ${configJson}
  EOF
  )

  CONFIG_JSON_GELF=$(cat <<'EOF'
    ${configJsonGelf}
  EOF
  )

  GENESIS_JSON=$(cat <<'EOF'
    ${genesisJson}
  EOF
  )

  GENESIS_SECRET_JSON=$(cat <<'EOF'
    ${genesisSecretJson}
  EOF
  )

  BFT_SECRET_JSON=$(cat <<'EOF'
    ${bftSecretJson}
  EOF
  )

  # Log ids
  LOGS_ID=$(uuidgen)
  CONFIG_JSON=$(echo "$CONFIG_JSON" | sed -e "s/LOGS_ID/$LOGS_ID/g" )
  CONFIG_JSON_GELF=$(echo "$CONFIG_JSON_GELF" | sed -e "s/LOGS_ID/$LOGS_ID/g" )

  mkdir -p secrets

  # Faucets '' + concatStrings (map (idx: let i = toString idx; in ''

  FAUCET_SK_${i}=$(jcli key generate --type=${if (block0_consensus == "bft") then "Ed25519" else "Ed25519Extended"})
  FAUCET_PK_${i}=$(echo $FAUCET_SK_${i} | jcli key to-public)
  echo $FAUCET_SK_${i} > secrets/stake_${i}_key.sk
  echo $FAUCET_PK_${i} > stake_${i}_key.pk
  FAUCET_ADDR_${i}=$(jcli address account $FAUCET_PK_${i} ${addrTypeFlag})
  '' + (if (block0_consensus == "bft") then ''
  echo "$BFT_SECRET_JSON" | sed -e "s/SIG_KEY/$FAUCET_SK_${i}/g" > secrets/secret_bft_stake_${i}.yaml
  '' else "") + ''
  GENESIS_JSON=$(echo "$GENESIS_JSON" | sed -e "s/\"FAUCET_ADDR_${i}\"/\"$FAUCET_ADDR_${toString i}\"/g" )

  '') (range 1 numberOfFaucets)) + ''

  # Leaders: '' + concatStrings (map (idx: let i = toString idx; in ''

  LEADER_SK_${i}=$(jcli key generate --type=Ed25519)
  echo $LEADER_SK_${i} > secrets/leader_${i}_key.sk
  LEADER_PK_${i}=$(echo $LEADER_SK_${i} | jcli key to-public)
  GENESIS_JSON=$(echo "$GENESIS_JSON" | sed -e "s/\"LEADER_PK_${i}\"/\"$LEADER_PK_${i}\"/g" )
  echo "$BFT_SECRET_JSON" | sed -e "s/SIG_KEY/$LEADER_SK_${i}/g" > secrets/secret_bft_leader_${i}.yaml

  '') (range 1 numberOfLeaders)) + ''

  # stake pools '' + concatStrings (map (idx: let i = toString idx; in ''

  POOL_VRF_SK_${i}=$(jcli key generate --type=Curve25519_2HashDH)
  POOL_KES_SK_${i}=$(jcli key generate --type=SumEd25519_12)

  POOL_VRF_PK_${i}=$(echo $POOL_VRF_SK_${i} | jcli key to-public)
  POOL_KES_PK_${i}=$(echo $POOL_KES_SK_${i} | jcli key to-public)

  # note we use the faucet as the owner to this pool
  STAKE_KEY_${i}=$FAUCET_SK_${i}
  STAKE_KEY_PUB_${i}=$FAUCET_PK_${i}

  echo $POOL_VRF_SK_${i} > secrets/stake_pool_${i}.vrf.sk
  echo $POOL_KES_SK_${i} > secrets/stake_pool_${i}.kes.sk

  jcli certificate new stake-pool-registration \
      --kes-key $POOL_KES_PK_${i} \
      --vrf-key $POOL_VRF_PK_${i} \
      --serial 1010101010 > stake_pool_${i}.cert

  cat stake_pool_${i}.cert | jcli certificate sign secrets/stake_${i}_key.sk > stake_pool_${i}.signcert

  STAKE_POOL_ID_${i}=$(cat stake_pool_${i}.signcert | jcli certificate get-stake-pool-id)

  STAKE_POOL_CERT_${i}=$(cat stake_pool_${i}.signcert)

  jcli certificate new stake-delegation \
      $STAKE_POOL_ID_${i} \
      $STAKE_KEY_PUB_${i} > stake_delegation.cert
  cat stake_delegation.cert | jcli certificate sign secrets/stake_${i}_key.sk > stake_${i}_delegation.signcert
  STAKE_DELEGATION_CERT_${i}=$(cat stake_${i}_delegation.signcert)

  echo "$GENESIS_SECRET_JSON" | sed -e "s/SIG_KEY/$POOL_KES_SK_${i}/g" | sed -e "s/VRF_KEY/$POOL_VRF_SK_${i}/g" |  sed -e "s/NODE_ID/$STAKE_POOL_ID_${i}/g" > secrets/secret_pool_${i}.yaml
  GENESIS_JSON=$(echo "$GENESIS_JSON" | sed -e "s/\"STAKE_POOL_CERT_${i}\"/\"$STAKE_POOL_CERT_${i}\"/g" )
  GENESIS_JSON=$(echo "$GENESIS_JSON" | sed -e "s/\"STAKE_DELEGATION_CERT_${i}\"/\"$STAKE_DELEGATION_CERT_${i}\"/g" )

  '') (range 1 numberOfStakePools))
  + ''

  echo "$CONFIG_JSON" > config.yaml
  echo "$CONFIG_JSON_GELF" > config-gelf.yaml
  echo "$GENESIS_JSON" > genesis.yaml
  echo "$GENESIS_JSON" | jcli genesis encode --output block-0.bin
  BLOCK0_HASH=`jcli genesis hash --input block-0.bin`

  process_file() {
      FROM=''${1}
      TO=''${2}

      sed -e "s/####FAUCET_SK####/''${FAUCET_SK_1}/" \
          -e "s/####BLOCK0_HASH####/''${BLOCK0_HASH}/" \
          -e "s;####REST_URL####;${httpHost};" \
          -e "s;####CLI####;jcli;" \
          -e "s/####COLORS####/${if color then "1" else "0"}/" \
          -e "s/####FEE_CONSTANT####/${toString linear_fees_constant}/" \
          -e "s/####FEE_CERTIFICATE####/${toString linear_fees_certificate}/" \
          -e "s/####FEE_COEFFICIENT####/${toString linear_fees_coefficient}/" \
          -e "s/####ADDRTYPE####/${addrTypeFlag}/" \
          -e "s/####STAKE_POOL_ID####/''${STAKE_POOL_ID_1}/" \
          < ''${FROM} > ''${TO}

      chmod +x ''${TO}
  }

  process_file "${jcli}/scripts/faucet-send-money.shtempl" faucet-send-money.sh
  process_file "${jcli}/scripts/faucet-send-certificate.shtempl" faucet-send-certificate.sh
  process_file "${jcli}/scripts/create-account-and-delegate.shtempl" create-account-and-delegate.sh

  if [ -d "${storage}" ]; then
    rm -r "${storage}"
  fi
''
