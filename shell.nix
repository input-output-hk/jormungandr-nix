let
  myPkgs = import ./.;
  rustPkgs = myPkgs.iohkNix.rust-packages.pkgs;
  pkgs = myPkgs.iohkNix.pkgs;
  baseConfig = import ./configs/base-default-config.nix;
  exempleConfigJson = builtins.toJSON baseConfig;
in pkgs.stdenv.mkDerivation {
  name = "jormungandr-demo";
  buildInputs = with pkgs; [
    rustPkgs.jormungandr remarshal
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
    jcli key generate --type=Ed25519Extended | tee secrets/stake.key | jcli key to-public > secrets/stake.pub
    jcli key generate --type=Curve25519_2HashDH | tee secrets/stake_pool_vrf.key | jcli key to-public > secrets/stake_pool_vrf.pub
    jcli key generate --type=SumEd25519_12 | tee secrets/stake_pool_kes.key | jcli key to-public > secrets/stake_pool_kes.pub
    jcli certificate new stake-pool-registration \
          --kes-key $(cat secrets/stake_pool_kes.pub) \
          --vrf-key $(cat secrets/stake_pool_vrf.pub) \
          --serial 1010101010 > secrets/stake_pool.cert
    cat secrets/stake_pool.cert | jcli certificate sign secrets/stake.key | tee secrets/stake_pool.cert
    cat secrets/stake_pool.cert | jcli certificate get-stake-pool-id | tee secrets/stake_pool.id
    Create Single address in staking key (for funds):
    jcli address single $(cat secrets/stake.key) > secrets/stake.address
    Generate genesis and edit with initial certs and stake:
    jcli genesis init > secrets/genesis.yaml
    Encode genesis block:
    jcli genesis encode --input secrets/genesis.yaml --output secrets/block-0.bin
    Create node config, example:
  EOF
  json2yaml << 'EOF'
    ${exempleConfigJson}
  EOF
  cat << 'EOF'
    Create secret:
    TBD
    Start jormungandr:
    jormungandr --genesis-block secrets/block-0.bin \
                --config config.yaml \
                --secret secrets/secret.yaml
  EOF
  '';
}
