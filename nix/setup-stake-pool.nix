{
  stdenv,
  writeScriptBin,
  jormungandr
}:

writeScriptBin "setup-stake-pool" ''
  #!${stdenv.shell} -e
  export PATH=${stdenv.lib.makeBinPath [ jormungandr ]}:$PATH
  if [ -z $1 ]
  then
    echo 'Pool name is required'
    exit 1
  fi
  POOLNAME=$1
  POOLDIR="stake-pools/$POOLNAME"
  echo "This script generates keys, a signed cert and node ID for use with a stake pool. All files will be output in $POOLDIR directory."
  if [ ! -d $POOLDIR ]
  then
    mkdir -p "$POOLDIR"
  else
    echo "Staking keys for $POOLNAME already exist. Exiting!"
    exit 1
  fi
  set -x
  jcli key generate --type=Ed25519Extended | tee $POOLDIR/stake.key | jcli key to-public > $POOLDIR/stake.pub
  jcli key generate --type=Curve25519_2HashDH | tee $POOLDIR/stake_pool_vrf.key | jcli key to-public > $POOLDIR/stake_pool_vrf.pub
  jcli key generate --type=SumEd25519_12 | tee $POOLDIR/stake_pool_kes.key | jcli key to-public > $POOLDIR/stake_pool_kes.pub
  jcli certificate new stake-pool-registration \
       --kes-key $(cat $POOLDIR/stake_pool_kes.pub) \
       --vrf-key $(cat $POOLDIR/stake_pool_vrf.pub) \
       --serial 1010101010 > $POOLDIR/stake_pool.cert
  cat $POOLDIR/stake_pool.cert | jcli certificate sign $POOLDIR/stake.key | tee $POOLDIR/stake_pool.cert
  cat $POOLDIR/stake_pool.cert | jcli certificate get-stake-pool-id | tee $POOLDIR/stake_pool.id
''
