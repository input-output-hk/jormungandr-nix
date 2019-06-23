with import ./lib.nix; with lib;
{ packageName ? "jormungandr"
, dockerEnv ? false
, package ? rustPkgs."${packageName}"
, block0_consensus ? "genesis"
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
, linear_fees_constant ? null
, linear_fees_coefficient ? null
, linear_fees_certificate ? null
, kes_update_speed ? null
# Same for make-config.nix
, storage ? null
, rest_listen ? "127.0.0.1:8443"
, rest_prefix ? "api"
, logger_verbosity ? null
, logger_format ? null
, logger_output ? null
, logger_backend ? null
, logs_id ? null
, public_address ? null
, trusted_peers ? null
, topics_of_interests ? if (numberOfStakePools > 0)  
    then "messages=high,blocks=high" 
    else "messages=low,blocks=normal"
}@args:
let
  
  genesisGeneratedArgs = {
    inherit block0_consensus;
    consensus_leader_ids = map (i: "LEADER_PK_${toString i}") (range 1 numberOfLeaders);
    initial = imap1 (i: a: { fund = { 
        address =  "FAUCET_ADDR_${toString i}";
        value = a;};}) faucetAmounts
      ++ concatMap (i: [
      { cert = "STAKE_POOL_CERT_${toString i}"; }
      { cert = "STAKE_DELEGATION_CERT_${toString i}"; }]) (range 1 (numberOfStakePools));
  };
  genesisJson = (pkgs.callPackage ./nix/make-genesis.nix (genesisGeneratedArgs // args));

  baseDirName = "jormungandr-" + (builtins.hashString "md5" (builtins.toJSON (builtins.removeAttrs args ["color" "dockerEnv"])));
  baseDir = rootDir + "/" + baseDirName;
  archiveFileName = baseDirName + "-config.zip";

  configGeneratedArgs = { 
    inherit topics_of_interests rest_listen rest_prefix;
    logs_id = if (logs_id == null) then "LOGS_ID" else logs_id;
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

  runCmd = "jormungandr --genesis-block block-0.bin --config config.yaml " + (concatMapStrings (i: 
      "--secret secrets/secret_pool_${toString i}.yaml "
    ) (range 1 (numberOfStakePools))) + (if (block0_consensus == "bft") then (concatMapStrings (i: 
      "--secret secrets/secret_bft_stake_${toString i}.yaml "
    ) (range 1 (builtins.length faucetAmounts))) else "")+ (concatMapStrings (i: 
      "--secret secrets/secret_bft_leader_${toString i}.yaml "
    ) (range 1 (numberOfLeaders)));

  header = (if color then ''\
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
    echo ""
  '';

  gen-config-script-fragement-non-nixos = pkgs.callPackage ./nix/generate-config.nix (args // {
    inherit genesisJson configJson genesisSecretJson bftSecretJson baseDir numberOfStakePools numberOfLeaders block0_consensus;
    numberOfFaucets = builtins.length faucetAmounts;  
  });

in rec {

  jcli = rustPkgs."${packageName}-cli";

  gen-config-script = with pkgs; writeScriptBin "generate-config" (''
    #!${stdenv.shell}

    set -euo pipefail
    
    export PATH=${stdenv.lib.makeBinPath [ jcli package remarshal zip utillinux ]}:$PATH
  '' + gen-config-script-fragement-non-nixos + ''
    cat genesis.yaml | json2yaml > genesis.yaml.json2yaml
    mv genesis.yaml.json2yaml genesis.yaml
    cat config.yaml | json2yaml > config.yaml.json2yaml
    mv config.yaml.json2yaml config.yaml

    if [ -f "${archiveFileName}" ]; then
      mv "${archiveFileName}" "${archiveFileName}.bak"
    fi
    zip -q -r "${archiveFileName}" block-0.bin config.yaml genesis.yaml secrets *cert
  '');

  run-jormungandr-script = with pkgs; writeScriptBin "run-jormungandr" (''
    #!${stdenv.shell}
    echo "Running ${runCmd}"
    ${package}/bin/${runCmd}
  '');

  jormungandr-bootstrap = with pkgs; writeScriptBin "jormungandr-bootstrap" (''
    #!/bin/sh
    
    OUTPUT="stderr"
    AUTOSTART=0
    while getopts 'la' c
    do
        case $c in
            a) AUTOSTART=1 ;;
            l) OUTPUT="gelf" ;;
            h)
                echo "usage: $0 [-a] [-l]"
                echo ""
                echo "  -a Auto-start jormungandr after generating config"
                echo "  -l Send logs to IOHK logs server for diagnostic purposes"
                exit 0
                ;;
        esac
      done

      ${header}

      if [ ! -f config.yaml ]; then
        ${gen-config-script-fragement-non-nixos}
      fi

      if [ "$OUTPUT" == "gelf" ]; then
         OUTPUT_ARG="--log-output gelf"
      else
         OUTPUT_ARG=""
      fi
      STARTCMD="${runCmd} $OUTPUT_ARG"

      if [ "$AUTOSTART" == "1" ]; then
        echo "Running"
        echo " $STARTCMD"
        echo ""
        $STARTCMD
      else
        echo "To start jormungandr run:"
        echo " $STARTCMD"
      fi
      
  '');

  shell = pkgs.stdenv.mkDerivation {
    name = "jormungandr-demo";
    
    buildInputs = with pkgs; [
      package
      rustPkgs."${packageName}-cli"
      gen-config-script
      run-jormungandr-script
      jormungandr-bootstrap 
    ] ++ lib.optional dockerEnv arionPkgs.arion;
    shellHook = ''
      echo "Jormungandr Demo" '' + (if color then ''\
      | ${pkgs.figlet}/bin/figlet -f banner -c \
      | ${pkgs.lolcat}/bin/lolcat'' else "") + ''

      mkdir -p "${baseDir}"
      cd "${baseDir}"

      ${header}

      '' + (if dockerEnv then ''
      mkdir -p docker
      if [ -L nixos ]; then
        rm nixos
      fi
      ln -sf "${./.}/nixos" nixos
      ln -sf "${./.}/docker/arion-pkgs.nix" docker/arion-pkgs.nix
      if [ ! -f ./docker/arion-compose.nix ]; then
        cp "${./.}/docker/arion-compose.nix" docker/
      fi
      '' else "") + ''
      if [ ! -f config.yaml ]; then
        generate-config
      fi
    '';
  };
}
 

