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
      default = "/var/lib/jormungandr/rewards";
      description = "Jormungandr reward dump directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.jormungandr-reward-api = {
      description = "API service for jormungandr rewards";

      wantedBy = [ "multi-user.target" ];

      environment = let
        penv = python.buildEnv.override {
          extraLibs = [ python.pkgs.watchdog python.pkgs.setuptools ];
        };
      in {
        PYTHONPATH = "${penv}/${python.sitePackages}";
        FLASK_APP = reward-api + "/app.py";
        JORMUNGANDR_REWARD_DUMP_DIRECTORY = cfg.dumpDir;
      };

      serviceConfig = {
        ExecStart = "${pkgs.python3Packages.flask}/bin/flask run --host=${cfg.host} --port=${toString cfg.port}";
      };
    };
  };

}
