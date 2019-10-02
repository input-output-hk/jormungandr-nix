{ config, pkgs, ... }:

let
  inherit (import ../../lib.nix)
    rustPkgs mkOption mkIf optionalAttrs concatMapStrings optionalString
    mkEnableOption types concatStringsSep filter makeBinPath;

  cfg = config.services.jormungandr;

  configFileOptions = {
    storage = "/var/lib/" + cfg.stateDir;

    log = {
      level = cfg.logger.level;
      format = cfg.logger.format;
      output = (if (cfg.logger.output == "gelf") then {
        gelf = {
          backend = cfg.logger.backend;
          log_id = cfg.logger.logs-id;
        };
      } else
        cfg.logger.output);
    };

    rest.listen = cfg.rest.listenAddress;

    p2p = {
      public_address = cfg.publicAddress;

      trusted_peers = cfg.trustedPeersAddresses;
      topics_of_interest = cfg.topicsOfInterest;
    } // optionalAttrs (cfg.listenAddress != null) {
      listen_address = cfg.listenAddress;
    };

    explorer.enabled = cfg.enableExplorer;
  };
in {
  options = {

    services.jormungandr = {
      enable = mkEnableOption "jormungandr";

      enableExplorer = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enables explorer graphql backend in jormungandr
        '';
      };

      package = mkOption {
        type = types.package;
        default = rustPkgs.pkgs.jormungandr;
        defaultText = "jormungandr";
        description = ''
          The jormungandr package that should be used.
        '';
      };

      stateDir = mkOption {
        type = types.str;
        default = "jormungandr";
        description = ''
          Directory below /var/lib to store blockchain data.
          This directory will be created automatically using systemd's StateDirectory mechanism.
        '';
      };

      genesisBlockHash = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Genesis Block Hash
        '';
      };

      block0 = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to the genesis block (the block0) of the blockchain.
        '';
      };

      secretsPaths = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "/var/lib/keys/faucet-key.yaml" ];
        description = ''
          Path to secret yaml.
        '';
      };

      topicsOfInterest.messages = mkOption {
        type = types.str;
        default = "low";
        description = ''
          notify other peers this node is interested about Transactions
          typical setting for a non mining node: "low".
          For a stakepool: "high".
        '';
      };
      topicsOfInterest.blocks = mkOption {
        type = types.str;
        default = "normal";
        description = ''
          notify other peers this node is interested about new Blocs.
          typical settings for a non mining node: "normal".
          For a stakepool: "high".
        '';
      };

      trustedPeersAddresses = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "/ip4/104.24.28.11/tcp/8299" ];
        description = ''
          the list of nodes to connect to in order to bootstrap the p2p topology
          (and bootstrap our local blockchain).
        '';
      };

      publicAddress = mkOption {
        type = types.str;
        default = "/ip4/127.0.0.1/tcp/8606";
        description = ''
          the address to listen from and accept connection from.
          This is the public address that will be distributed to other peers of the network
          that may find interest into participating to the blockchain dissemination with the node.
        '';
      };

      listenAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/ip4/0.0.0.0/tcp/8606";
        description = ''
          Local socket address to listen to, if different from public address.
          The IP address can be given as 0.0.0.0 or :: to bind to all
          network interfaces.
        '';
      };

      rest.listenAddress = mkOption {
        type = types.nullOr types.str;
        default = "127.0.0.1:8607";
        description = ''
          Address to listen on for rest endpoint.
        '';
      };

      logger.level = mkOption {
        type = types.enum [
          "off"
          "critical"
          "error"
          "warning"
          "info"
          "debug"
          "trace"
        ];
        default = "info";
        example = "debug";
        description = ''
          Logger level: "off", "critical", "error", "warn", "info", "debug", "trace"
        '';
      };

      logger.format = mkOption {
        type = types.str;
        default = "plain";
        example = "json";
        description = ''
          log output format - plain or json.
        '';
      };

      logger.output = mkOption {
        type = types.enum [ "stderr" "syslog" "journald" "gelf" ];
        default = "stderr";
        example = "syslog";
        description = ''
          log output - stderr, syslog (unix only) or journald (linux with systemd only, must be enabled during compilation).
        '';
      };

      logger.backend = mkOption {
        type = types.str;
        example = "monitoring.stakepool.cardano-testnet.iohkdev.io:12201";
        description = ''
          The graylog server to use as GELF backend.
        '';
      };

      logger.logs-id = mkOption {
        type = types.str;
        description = ''
          Used by gelf output as log source.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services."jormungandr@" = {
      description = "Jormungandr node service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        DynamicUser = true;
        User = "jormungandr";
        RestartSec = "10s";
        Restart = "always";
        WorkingDirectory = "/var/lib/" + cfg.stateDir;
        StateDirectory = cfg.stateDir;
      };

      environment.RUST_BACKTRACE = "full";

      serviceConfig.PermissionsStartOnly = true;
      preStart = ''
        for f in ${toString cfg.secretsPaths}; do
          cp $f /var/lib/private/${cfg.stateDir}
        done
        chmod 0600 /var/lib/private/${cfg.stateDir}/*
      '';

      script = let
        configJson =
          builtins.toFile "config.yaml" (builtins.toJSON configFileOptions);

        secretsArgs =
          concatStringsSep " " (map (p: ''--secret "${p}"'') cfg.secretsPaths);

        genesisBlockHash = optionalString (cfg.genesisBlockHash != null)
          "--genesis-block-hash ${cfg.genesisBlockHash}";

        genesisBlock =
          optionalString (cfg.block0 != null) "--genesis-block ${cfg.block0}";

        command = concatStringsSep " " (filter (s: s != "") [
          "${cfg.package}/bin/jormungandr"
          genesisBlock
          genesisBlockHash
          secretsArgs
        ]);
      in ''
        export PATH="$PATH:${makeBinPath (with pkgs; [ jq ])}"
        jq . ${configJson} > config.json
        ${command} --config $PWD/config.json
      '';
    };
  };
}
