{ block0_consensus ? "genesis"
, color ? true
, faucetAmounts ? [ 1000000000 ]
, numberOfStakePools ? if (block0_consensus == "bft") then 0 else (builtins.length faucetAmounts)
, numberOfLeaders ? 1
, rootDir ? "/tmp"
# need to declare other make-genesis.nix parameters to be able to pass them:
, block0_date ? null
, isProduction ? null
, slots_per_epoch ? null
, slot_duration ? null
, epoch_stability_depth ? null
, bft_slots_ratio ? null
, consensus_genesis_praos_active_slot_coeff ? null
, max_number_of_transactions_per_block ? null
, allow_account_creation ? null
, linear_fee_constant ? null
, linear_fee_coefficient ? null
, linear_fee_certificate ? null
, kes_update_speed ? null
# Same for make-config.nix
, storage ? null
, rest_listen ? "127.0.0.1:8443"
, rest_prefix ? "api"
, logger_verbosity ? null
, logger_format ? null
, public_address ? null
, trusted_peers ? null
, topics_of_interests ? if (numberOfStakePools > 0)  
    then "messages=high,blocks=high" 
    else "messages=low,blocks=normal"
}@args:
with import ./lib.nix; with lib;
let
  
  genesisGeneratedArgs =  {
    inherit block0_consensus;
    consensus_leader_ids = map (i: "LEADER_PK_${toString i}") (range 1 numberOfLeaders);
    initial_certs = concatMap (i: [
      "STAKE_POOL_CERT_${toString i}"
      "STAKE_DELEGATION_CERT_${toString i}"]) (range 1 (numberOfStakePools));
    initial_funds = imap1 (i: a: { 
      address =  "FAUCET_ADDR_${toString i}";
      value = a;}) faucetAmounts;
  };
  genesisJson = (pkgs.callPackage ./nix/make-genesis.nix (genesisGeneratedArgs // args));

  baseDirName = "jormungandr-" + (builtins.hashString "md5" (builtins.toJSON (builtins.removeAttrs args ["color"])));
  baseDir = rootDir + "/" + baseDirName;
  archiveFileName = baseDirName + "-config.zip";

  configGeneratedArgs = { 
    inherit topics_of_interests rest_listen rest_prefix;
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
    inherit genesisJson configJson genesisSecretJson bftSecretJson baseDir numberOfStakePools numberOfLeaders block0_consensus archiveFileName;
    numberOfFaucets = builtins.length faucetAmounts;
    inherit (rustPkgs) jormungandr;
  });

  open-archive = with pkgs; writeScriptBin "open-config-archive" (''
    #!${stdenv.shell}
    ${xdg_utils}/bin/xdg-open ${archiveFileName}
  '');

  runCmd = "jormungandr --genesis-block block-0.bin --config config.yaml " + (concatMapStrings (i: 
      "--secret secrets/secret_pool_${toString i}.yaml "
    ) (range 1 (numberOfStakePools))) + (if (block0_consensus == "bft") then (concatMapStrings (i: 
      "--secret secrets/secret_bft_stake_${toString i}.yaml "
    ) (range 1 (builtins.length faucetAmounts))) else "");

  run-jormungandr = with pkgs; writeScriptBin "run-jormungandr" (''
    #!${stdenv.shell}
    ${runCmd}
  '');

in pkgs.stdenv.mkDerivation {
  name = "jormungandr-demo";
  
  buildInputs = with pkgs; [
    rustPkgs.jormungandr
    gen-config
    # open-archive
    run-jormungandr
  ];
  shellHook = ''
    mkdir -p "${baseDir}"
    cd "${baseDir}"

    if [ ! -f "${archiveFileName}" ]; then
      generate-config
    fi

    echo "Jormungandr Demo" '' + (if color then ''\
    | ${pkgs.figlet}/bin/figlet -f banner -c \
    | ${pkgs.lolcat}/bin/lolcat
    GREEN=`printf "\033[0;32m"`
    RED=`printf "\033[0;31m"`
    BLUE=`printf "\033[0;33m"`
    WHITE=`printf "\033[0m"`
    '' else ''
    GREEN=""
    RED=""
    BLUE=""
    WHITE=""
    '') + ''
    
    echo "##############################################################################"
    echo "                                Configuration"
    echo ""
    echo "* Consensus: ''${RED}${block0_consensus}''${WHITE}"
    echo "* REST Port: ''${RED}${rest_listen}''${WHITE}"
    echo ""
    echo "##############################################################################"

  '';
}
