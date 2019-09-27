{ pkgs, lib, config, ... }:

let
  cfg = config.services.jormungandr-monitor;
  cfgJormungandr = config.services.jormungandr;

  genesisAddresses = let
    inherit (lib) elemAt filter readFile fromJSON;
    genesis = fromJSON (readFile cfg.genesisYaml);
    initial = map (i: if i ? fund then i.fund else null) genesis.initial;
    withFunds = filter (f: f != null) initial;
  in map (f: f.address) (lib.flatten withFunds);

  inherit (lib)
    mkIf mkOption types mkEnableOption concatStringsSep optionals optionalAttrs;
in {
  options = {
    services.jormungandr-monitor = {
      enable = mkEnableOption "jormungandr monitor";

      monitorAddresses = mkOption {
        type = types.listOf types.string;
        default = [ ];
      };

      jormungandrApi = mkOption {
        type = types.string;
        default = "http://${cfgJormungandr.rest.listenAddress}/api";
      };

      genesisYaml = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Extract addresses to monitor from this file if set";
      };

      port = mkOption {
        type = types.port;
        default = 8000;
      };
    };
  };

  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [ cfg.port ];

    systemd.services.jormungandr-monitor = {
      wantedBy = [ "multi-user.target" ];
      after = [ "jormungandr.service" ];

      environment = {
        PORT = toString cfg.port;
        JORMUNGANDR_API = cfg.jormungandrApi;
        MONITOR_ADDRESSES = concatStringsSep " "
          ((optionals (cfg.genesisYaml != null) genesisAddresses)
            ++ cfg.monitorAddresses);
      };

      serviceConfig = {
        User = "jormungandr-monitor";
        DynamicUser = true;
        StartLimitBurst = 50;
        ExecStart = pkgs.callPackage ./jormungandr-monitor { };
        Restart = "always";
        RestartSec = "15s";
      };
    };
  };
}
