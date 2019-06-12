{ stdenv
, lib
, writeScriptBin
, block0_consensus
, isProduction ? false
, addrTypeFlag ? if (isProduction) then "" else "--testing"
, numberOfFaucets
, numberOfStakePools
, numberOfLeaders
, configJson
, genesisJson
, genesisSecretJson
, bftSecretJson
, baseDir
, archiveFileName
, jormungandr
, remarshal
, zip
, ...
}:

with lib; writeScriptBin "generate-config" (''
  #!${stdenv.shell}

  set -euo pipefail
  
  export PATH=${stdenv.lib.makeBinPath [ jormungandr remarshal zip ]}:$PATH

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

  mkdir -p secrets

  # Faucets '' + concatStrings (map (idx: let i = toString idx; in ''

  FAUCET_SK_${i}=$(jcli key generate --type=Ed25519Extended)
  FAUCET_PK_${i}=$(echo $FAUCET_SK_${i} | jcli key to-public)
  echo $FAUCET_SK_${i} > secrets/stake_${i}_key.sk
  FAUCET_ADDR_${i}=$(jcli address account $FAUCET_PK_${i} ${addrTypeFlag})
  '' + (if (block0_consensus == "bft") then ''
  echo "$BFT_SECRET_JSON" | sed -e "s/SIG_KEY/$FAUCET_SK_${i}/g" | json2yaml > secrets/secret_bft_stake_${i}.yaml
  '' else "") + ''
  GENESIS_JSON=$(echo "$GENESIS_JSON" | sed -e "s/FAUCET_ADDR_${i}/$FAUCET_ADDR_${toString i}/g" )

  '') (range 1 numberOfFaucets)) + ''

  # Leaders: '' + concatStrings (map (idx: let i = toString idx; in ''

  LEADER_SK_${i}=$(jcli key generate --type=Ed25519)
  echo $LEADER_SK_${i} > secrets/leader_${i}_key.sk
  LEADER_PK_${i}=$(echo $LEADER_SK_${i} | jcli key to-public)
  GENESIS_JSON=$(echo "$GENESIS_JSON" | sed -e "s/LEADER_PK_${i}/$LEADER_PK_${i}/g" )
  
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

  echo "$GENESIS_SECRET_JSON" | sed -e "s/SIG_KEY/$POOL_KES_SK_${i}/g" | sed -e "s/VRF_KEY/$POOL_VRF_SK_${i}/g" |  sed -e "s/NODE_ID/$STAKE_POOL_ID_${i}/g" | json2yaml > secrets/secret_pool_${i}.yaml
  GENESIS_JSON=$(echo "$GENESIS_JSON" | sed -e "s/STAKE_POOL_CERT_${i}/$STAKE_POOL_CERT_${i}/g" )
  GENESIS_JSON=$(echo "$GENESIS_JSON" | sed -e "s/STAKE_DELEGATION_CERT_${i}/$STAKE_DELEGATION_CERT_${i}/g" )

  '') (range 1 numberOfStakePools))
  + ''

  json2yaml << 'EOF' > config.yaml
    ${configJson}
  EOF
  echo "$GENESIS_JSON" | json2yaml > genesis.yaml
  echo "$GENESIS_JSON" | jcli genesis encode --output block-0.bin

  if [ -f "${archiveFileName}" ]; then
    mv "${archiveFileName}" "${archiveFileName}.bak"
  fi
  zip -q -r "${archiveFileName}" block-0.bin config.yaml genesis.yaml secrets *cert
'')
