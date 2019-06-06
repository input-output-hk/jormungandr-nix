{ consensusMode ? "genesis"
, faucetAmounts ? [ 1000000000 ]
, numberOfStakePools ? if (consensusMode == "bft") then 0 else (builtins.length faucetAmounts)
, numberOfLeaders ? 1
, rootDir ? "/tmp"
# need to declare other make-genesis.nix parameters to be able to pass them:
, startDate ? null
, isProduction ? null
, slotsPerEpoch ? null
, slotDuration ? null
, epochStabilityDepth ? null
, bftSlotsRatio ? null
, consensusGenesisPraosActiveSlotCoeff ? null
, maxTx ? null
, allowAccountCreation ? null
, linearFeeConstant ? null
, linearFeeCoefficient ? null
, linearFeeCert ? null
, kesUpdateSpeed ? null
# Same for make-config.nix
, storage ? null
, httpListen ? null
, httpPrefix ? null
, loggerVerbosity ? null
, loggerFormat ? null
, publicAddress ? null
, peerAddresses ? null
, topicsOfInterests ? if (numberOfStakePools > 0)  
    then "messages=high,blocks=high" 
    else "messages=low,blocks=normal"
}@args:
with import ./lib.nix; with lib;
let
  
  genesisGeneratedArgs =  {
    inherit consensusMode;
    consensusLeaderIds = map (i: "LEADER_PK_${toString i}") (range 1 numberOfLeaders);
    initialCerts = concatMap (i: [
      "STAKE_POOL_CERT_${toString i}"
      "STAKE_DELEGATION_CERT_${toString i}"]) (range 1 (numberOfStakePools));
    faucets = imap1 (i: a: { 
      address =  "FAUCET_ADDR_${toString i}";
      value = a;}) faucetAmounts;
  };
  genesisJson = (pkgs.callPackage ./nix/make-genesis.nix (genesisGeneratedArgs // args));

  baseDir = rootDir + "/jormungandr-" + (builtins.hashString "md5" (builtins.toJSON args));

  configGeneratedArgs = { 
    inherit topicsOfInterests;
    storage = baseDir + "/storage";
  };
  configJson = pkgs.callPackage ./nix/make-config.nix (configGeneratedArgs // args);

  genesisSecretJson = pkgs.callPackage ./nix/make-genesis-secret.nix {
    sigKey = "SIG_KEY";
    vrfKey = "VRF_KEY";
    nodeId = "NODE_ID";
  };

  bftSecretJson = pkgs.callPackage ./nix/make-bft-secret.nix {
    sigKey = "SIG_KEY";
  };

  gen-config = pkgs.callPackage ./nix/generate-config.nix (args // {
    inherit genesisJson configJson genesisSecretJson bftSecretJson baseDir numberOfStakePools numberOfLeaders consensusMode;
    numberOfFaucets = builtins.length faucetAmounts;
    inherit (rustPkgs) jormungandr;
  });
  myPkgs = import ./. args;
in pkgs.stdenv.mkDerivation {
  name = "jormungandr-demo";
  
  buildInputs = with pkgs; [
    remarshal
    rustPkgs.jormungandr
    gen-config
    myPkgs.setupStakePool
  ];
  shellHook = ''
  mkdir -p "${baseDir}"
  cd "${baseDir}"
 
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
