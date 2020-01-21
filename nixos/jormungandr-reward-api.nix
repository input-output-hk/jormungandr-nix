# NixOS service for jormungandr-reward-api

{ lib, pkgs, config, ... }:

with lib;
let
  cfg = config.services.jormungandr-reward-api;
  reward-api = import ../reward-api;
in {
  options.services.jormungandr-reward-api = {
    enable = mkEnableOption "Jormungandr Rewards service";

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    port = mkOption {
      type = types.int;
      default = 5000;
    };

    dumpDir = mkOption {
      type = types.str;
      default = "/var/lib/jormungandr/rewards";
      description = "Jormungandr reward dump directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.jormungandr-reward-api = {
      description = "API service for jormungandr rewards";

      wantedBy = [ "multi-user.target" ];

      environment = {
        JORMUNGANDR_REWARD_DUMP_DIRECTORY = cfg.dumpDir;
        JORMUNGANDR_RESTAPI_URL = "http://${config.services.jormungandr.rest.listenAddress}/api";
        JORMUNGANDR_GRAPHQL_URL = "http://${config.services.jormungandr.rest.listenAddress}/explorer/graphql";
        KEMAL_ENV = "production";
      };

      serviceConfig = {
        ExecStart = "${reward-api}/bin/reward-api --bind ${cfg.host} --port ${toString cfg.port}";
        LimitNOFILE = "16384";
        Restart = "always";
      };
    };
  };
}
