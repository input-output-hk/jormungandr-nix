let
  myPkgs = import ./.;
  pkgs = myPkgs.iohkNix.rust-packages.pkgs;
in pkgs.stdenv.mkDerivation {
  name = "jormungandr-demo";
  buildInputs = with pkgs; [
    jormungandr
  ];
  shellHook = ''
  echo "Jormungandr Demo" \
  | ${pkgs.figlet}/bin/figlet -f banner -c \
  | ${pkgs.lolcat}/bin/lolcat
  cat << 'EOF'
  Instructions for Starting one-node genesis cluster:
    Create Wallet:
    TBD
    Create Wallet Delegation:
    TBD
    Create Staking Pool KES Keys and Stake Pool Certificate:
    jcli key generate --type=Ed25519Extended | tee stake.key | jcli key to-public > stake.pub
    jcli key generate --type=Curve25519_2HashDH | tee stake_pool_vrf.key | jcli key to-public > stake_pool_vrf.pub
    jcli key generate --type=SumEd25519_12 | tee stake_pool_kes.key | jcli key to-public > stake_pool_kes.pub
    jcli certificate new stake-pool-registration \
          --kes-key $(cat stake_pool_kes.pub) \
          --vrf-key $(cat stake_pool_vrf.pub) \
          --serial 1010101010 > stake_pool.cert
    cat stake_pool.cert | jcli certificate sign stake.key | tee stake_pool.cert
    cat stake_pool.cert | jcli certificate get-stake-pool-id | tee stake_pool.id
    Create Single address in staking key (for funds):
    jcli address single $(cat stake.key) > stake.address
    Generate genesis and edit with initial certs and stake:
    jcli genesis init > genesis.yaml
    Encode genesis block:
    jcli genesis encode --input genesis.yaml --output block-0.bin
    Create node config:
    TBD
    Create secret:
    TBD
    Start jormungandr:
    jormungandr --genesis-block block-0.bin \
    --config config.yaml \
    --secret node_secret.yaml
  EOF
  '';
}
