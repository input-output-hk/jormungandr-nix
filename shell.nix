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

  baseDirName = "jormungandr-" + (builtins.hashString "md5" (builtins.toJSON args));
  baseDir = rootDir + "/" + baseDirName;
  archiveFileName = baseDirName + "-config.zip";

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
    inherit genesisJson configJson genesisSecretJson bftSecretJson baseDir numberOfStakePools numberOfLeaders consensusMode archiveFileName;
    numberOfFaucets = builtins.length faucetAmounts;
    inherit (rustPkgs) jormungandr;
  });

  open-archive = with pkgs; writeScriptBin "open-config-archive" (''
    #!${stdenv.shell}
    ${xdg_utils}/bin/xdg-open ${archiveFileName}
  '');

in pkgs.stdenv.mkDerivation {
  name = "jormungandr-demo";
  
  buildInputs = with pkgs; [
    rustPkgs.jormungandr
    gen-config
    open-archive
  ];
  shellHook = ''
    mkdir -p "${baseDir}"
    cd "${baseDir}"

    if [ ! -f "${archiveFileName}" ]; then
      generate-config
    fi
  '';
}
