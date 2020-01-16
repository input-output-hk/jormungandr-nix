# NixOS service for jormungandr-reward-api

{ lib, pkgs, config, ... }:

with lib;
let
  cfg = config.services.jormungandr-reward-api;
  python = pkgs.python3;
  reward-api = pkgs.callPackage ../reward-api {};
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
      default = "rewards";
      description = "Jormungandr reward dump directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.jormungandr-reward-api = {
      description = "API service for jormungandr rewards";

      wantedBy = [ "multi-user.target" ];

      environment = let
        penv = python.buildEnv.override {
          extraLibs = with python.pkgs; [ flask gunicorn watchdog setuptools requests ];
        };
      in {
        PYTHONPATH = "${penv}/${python.sitePackages}:${reward-api}";
        FLASK_APP = reward-api + "/app.py";
        JORMUNGANDR_REWARD_DUMP_DIRECTORY = cfg.dumpDir;
        JORMUNGANDR_RESTAPI_URL = "http://${config.services.jormungandr.rest.listenAddress}/api";
      };

      serviceConfig = {
        User = "jormungandr";
        Group = "jormungandr";
        ExecStart = "${pkgs.python3Packages.gunicorn}/bin/gunicorn -w 4 -b ${cfg.host}:${toString cfg.port} wsgi:app";
        WorkingDirectory = "/var/lib/jormungandr";
      };
    };
  };

}
