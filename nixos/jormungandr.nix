{ config
, pkgs
, lib
, ... }:

with lib;
let
  cfg = config.services.jormungandr;
  commonLib = import ../lib.nix;
  environments = (commonLib).environments;
in {
  options = {

    services.jormungandr = {
      enable = mkEnableOption "jormungandr";

      environment = mkOption {
        type = types.str;
        default = "itn_rewards_v1";
        description = ''
          Environment in jormungandrLib to pull configuration from.
        '';
      };

      enableExplorer = mkEnableOption "explorer";
      enableRewardsLog = mkEnableOption "rewards log";

      package = mkOption {
        type = types.package;
        default = environments.${cfg.environment}.packages.jormungandr;
        defaultText = "jormungandr";
        description = ''
          The jormungandr package that should be used.
        '';
      };

      jcliPackage = mkOption {
        type = types.package;
        default = environments.${cfg.environment}.packages.jcli;
        defaultText = "jormungandr-cli";
        description = ''
          The jormungandr-cli package that should be used.
        '';
      };

      withBackTraces = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Run with RUST_BACKTRACE=1.
        '';
      };

      withValgrind = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Run with valgrind.
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
        default = if (cfg.block0 != null) then null else environments.${cfg.environment}.genesisHash;
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

      secrets-paths = mkOption {
        type = types.listOf types.str;
        default = [];
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

      trustedPeers = mkOption {
        type = types.listOf (types.submodule {
          options = {
            address = mkOption {
              type = types.str;
              description = ''
                IP address in the format of:
                /ip4/127.0.0.1/tcp/8080 or /ip6/::1/tcp/8080
              '';
            };

            id = mkOption {
              type = types.str;
              description = ''
                public key of the node
              '';
            };
          };
        });
        default = environments.${cfg.environment}.trustedPeers;
        description = ''
          the list of nodes to connect to in order to bootstrap the p2p topology
          (and bootstrap our local blockchain).
        '';
      };

      policyQuarantineDuration = mkOption {
        type = types.str;
        default = "30m";
        description = ''
          Time a node is quarantined before being allowed to reconnect
        '';
      };

      maxUnreachableNodes = mkOption {
        type = types.int;
        default = 20;
        description = ''
          Number of nodes that aren't public we will allow our node to connect
        '';
      };

      gossipInterval = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      topologyForceResetInterval = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Force reset topology at an interval
          WARNING: do not change unless you know what you're doing
        '';
      };

      publicId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Needed to make a node publicly reachable.
          Generate with `openssl rand -hex 24`.
        '';
      };

      publicAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          the address to listen from and accept connection from.
          This is the public address that will beenvironments.${cfg.environment} distributed to other peers of the network
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

      maxConnections = mkOption {
        type = types.nullOr types.int;
        default = null;
        example = 500;
        description = ''
          Max connections allowed
        '';
      };

      rest.listenAddress = mkOption {
        type = types.nullOr types.str;
        default = "127.0.0.1:8607";
        description = ''
          Address to listen on for rest endpoint.
        '';
      };

      rest.cors.allowedOrigins = mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "yourhostname.com" ];
        description = ''
          CORS allowed origins
        '';
      };

      logger.level = mkOption {
        type = types.enum [ "off" "critical" "error" "warn" "info" "debug" "trace"];
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
    environment.systemPackages = [
      cfg.jcliPackage
    ];
    users.groups.jormungandr.gid = 10015;
    users.users.jormungandr = {
      description = "Jormungandr node daemon user";
      uid = 10015;
      group = "jormungandr";
    };
    systemd.services.jormungandr = {
      description   = "Jormungandr node service";
      after         = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      script = let
        configJson = builtins.toFile "config.yaml" (builtins.toJSON ({
          storage = "/var/lib/" + cfg.stateDir;
          log = [{
            level = cfg.logger.level;
            format = cfg.logger.format;
            output = (if (cfg.logger.output == "gelf") then {
              gelf = {
                backend = cfg.logger.backend;
                log_id = cfg.logger.logs-id;
              };
            } else cfg.logger.output);
          }];

          rest = {
            listen = cfg.rest.listenAddress;
          } // optionalAttrs (cfg.rest.cors.allowedOrigins != []) {
            cors.allowed_origins = cfg.rest.cors.allowedOrigins;
          };

          p2p = filterAttrs (key: value: value != null) {
            public_address = cfg.publicAddress;
            public_id = cfg.publicId;

            trusted_peers = map (peer: {
              address = peer.address;
              id = peer.id;
            }) cfg.trustedPeers;
            topics_of_interest = cfg.topicsOfInterest;
            listen_address = cfg.listenAddress;
            max_connections = cfg.maxConnections;
            policy = {
              quarantine_duration = cfg.policyQuarantineDuration;
            };
            max_unreachable_nodes_to_connect_per_event = cfg.maxUnreachableNodes;
          } // optionalAttrs (cfg.topologyForceResetInterval != null) {
            topology_force_reset_interval = cfg.topologyForceResetInterval;
          };
        } // optionalAttrs cfg.enableExplorer {
          explorer = {
            enabled = true;
          };
        }));
        secretsArgs = concatMapStrings (p: " --secret \"${p}\"") cfg.secrets-paths;
      in ''
        ${optionalString cfg.enableRewardsLog "mkdir -p /var/lib/${cfg.stateDir}/rewards\nexport JORMUNGANDR_REWARD_DUMP_DIRECTORY=/var/lib/${cfg.stateDir}/rewards"}
        ${optionalString cfg.withBackTraces "RUST_BACKTRACE=full"} exec ${optionalString cfg.withValgrind "${pkgs.valgrind}/bin/valgrind"} ${cfg.package}/bin/jormungandr \
        ${optionalString (cfg.block0 != null) "--genesis-block ${cfg.block0}"} \
        ${optionalString (cfg.genesisBlockHash != null) "--genesis-block-hash ${cfg.genesisBlockHash}"} \
        --config ${configJson}${secretsArgs}
      '';
      serviceConfig = {
        User = "jormungandr";
        Group = "jormungandr";
        Restart = "always";
        WorkingDirectory = "/var/lib/" + cfg.stateDir;
        StateDirectory = cfg.stateDir;
        LimitNOFILE = "16384";
      };
    };
  };
}
