{ pkgs, lib, config, ... }:

let
  cfg = config.services.jormungandr-monitor;
  cfgJormungandr = config.services.jormungandr;
  genesisAddresses = let
    inherit (builtins) fromJSON elemAt filter readFile;
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
        type = types.listOf types.str;
        default = [ ];
      };

      jcliPackage = mkOption {
        type = types.package;
        default = (import ../lib.nix).packages.release.jcli;
      };

      jormungandrApi = mkOption {
        type = types.str;
        default = "http://${cfgJormungandr.rest.listenAddress}/api";
      };

      genesisYaml = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Extract addresses to monitor from this file if set";
      };

      genesisAddrSelector = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = ''
          A specific single address to monitor from the genesis yaml list (1-indexed).
          If the genesisYaml option is utilized and this genesisAddrSelector is not
          provided, the full list of addresses will be monitored.
        '';
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
          ((optionals (cfg.genesisYaml != null) (
            if (cfg.genesisAddrSelector != null) then
              [ (__elemAt genesisAddresses (cfg.genesisAddrSelector - 1)) ]
            else
              genesisAddresses))
            ++ cfg.monitorAddresses);
      };

      serviceConfig = {
        User = "jormungandr-monitor";
        DynamicUser = true;
        StartLimitBurst = 50;
        ExecStart = pkgs.callPackage ./jormungandr-monitor { jormungandr-cli = cfg.jcliPackage; };
        Restart = "always";
        RestartSec = "15s";
      };
    };
  };
}
