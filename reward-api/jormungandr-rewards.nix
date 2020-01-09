# NixOS service for jormungandr-rewards

{ lib, pkgs, config, ... }:

with lib;
let
  cfg = config.services.jormungandr-rewards;
  python = pkgs.python3;
in {
  options.services.jormungandr-rewards = {
    enable = mkEnableOption "Jormungandr Rewards service";

    # Path currently hard coded until appropriate paths are determined
    jormungandrNix = mkOption {
      type = types.str;
      default = "/home/craige/source/IOHK/jormungandr-nix";
      description = "Directory jormungandr-nix can be found";
    };

    flaskApp = mkOption {
      type = types.str;
      default = "${cfg.jormungandrNix}/reward-api/app.py";
      description = "Location of the rewards application for flask";
    };

    dumpDir = mkOption {
      type = types.str;
      default = "${cfg.jormungandrNix}/state-jormungandr-qa/rewards";
      description = "Jormungandr reward dump directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.jormungandr-rewards = {
      description = "API service for jormungandr rewards";

      wantedBy = [ "multi-user.target" ];

      environment = let
        penv = python.buildEnv.override {
          extraLibs = [ python.pkgs.watchdog python.pkgs.setuptools ];
        };
      in {
        PYTHONPATH = "${penv}/${python.sitePackages}";
        FLASK_APP = cfg.flaskApp;
        JORMUNGANDR_REWARD_DUMP_DIRECTORY = cfg.dumpDir;
      };

      serviceConfig = {
        ExecStart = "${pkgs.python3Packages.flask}/bin/flask run";
      };
    };
  };

}
