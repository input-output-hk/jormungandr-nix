let
  myPkgs = import ./.;
  pkgs = myPkgs.iohkNix.rust-packages.pkgs;
in pkgs.stdenv.mkDerivation {
  name = "jormungandr-demo";
  buildInputs = with pkgs; [
    jormungandr
    myPkgs.setupStakePool
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
    setup-stake-pool
    Create Single address in staking key (for funds):
    jcli address single $(cat secrets/stake.key) > secrets/stake.address
    Generate genesis and edit with initial certs and stake:
    jcli genesis init > secrets/genesis.yaml
    Encode genesis block:
    jcli genesis encode --input secrets/genesis.yaml --output secrets/block-0.bin
    Create node config:
    TBD
    Create secret:
    TBD
    Start jormungandr:
    jormungandr --genesis-block secrets/block-0.bin \
                --config config.yaml \
                --secret secrets/secret.yaml
  EOF
  '';
}
