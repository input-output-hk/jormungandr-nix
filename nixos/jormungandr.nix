{ config
, pkgs
, lib
, ... }:

with lib;
let
  cfg = config.services.jormungandr;
in {
  options = {

    services.jormungandr = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable jormungandr, a node implementing ouroboros protocols
          (the blockchain protocols running cardano).
        '';
      };

      package = mkOption {
        type = types.package;
        default = (import ../lib.nix).pkgs.jormungandr;
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

      block0 = mkOption {
        type = types.path;
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

      topicsOfInterests.messages = mkOption {
        type = types.str;
        default = "low";
        description = ''
          notify other peers this node is interested about Transactions
          typical setting for a non mining node: "low".
          For a stakepool: "high".
        '';
      };
      topicsOfInterests.blocks = mkOption {
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
        default = [];
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

      publicId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          the public identifier send to the other nodes in the p2p network.
          If not set it will be randomly generated.
        '';
      };

      rest.listenAddress = mkOption {
        type = types.nullOr types.str;
        default = "127.0.0.1:8607";
        description = ''
          Address to listen on for rest endpoint.
        '';
      };

      rest.prefix = mkOption {
        type = types.str;
        default = "api";
        description = ''
          Http prefix of the rest api.
        '';
      };

      logger.verbosity = mkOption {
        type = types.int;
        default = 1;
        example = 3;
        description = ''
          Logger verbosity 0 - warning, 1 - info, 2 -debug, 3 and above - trace.
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
        type = types.str;
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
        configJson = builtins.toFile "config.yaml" (builtins.toJSON {
          storage = "/var/lib/" + cfg.stateDir;
          logger = {
            verbosity = cfg.logger.verbosity;
            format = cfg.logger.format;
            output = (if (cfg.logger.output == "gelf") then {
              gelf = {
                backend = cfg.logger.backend;
                logs_id = cfg.logger.logs-id;
              };
            } else cfg.logger.output);
          };
          rest = {
            listen = cfg.rest.listenAddress;
            prefix = cfg.rest.prefix;
          };
          peer_2_peer = {
            public_address = cfg.publicAddress;
            trusted_peers = cfg.trustedPeersAddresses;
            topics_of_interests = cfg.topicsOfInterests;
          } // (if (cfg.publicId != null) then {
            public_id = cfg.publicId;
          } else {});
        });
        secretsArgs = lib.concatMapStrings (p: " --secret \"${p}\"") cfg.secrets-paths;
      in ''
        ${cfg.package}/bin/jormungandr --genesis-block ${cfg.block0} --config ${configJson}${secretsArgs}
      '';
      serviceConfig = {
        User = "jormungandr";
        Group = "jormungandr";
        Restart = "always";
        WorkingDirectory = "/var/lib/" + cfg.stateDir;
        StateDirectory = cfg.stateDir;
      };
    };
  };
}
