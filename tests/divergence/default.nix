let
  sources = import ../../nix/sources.nix;
  lib = ( import ../../lib.nix ).lib;
  inherit (lib)
    rustPkgs mapAttrs flip concatStringsSep attrValues range
    listToAttrs optionalString optionals filter makeBinPath flatten
    optionalAttrs recursiveUpdate pkgs take;
  inherit (builtins) foldl';
  inherit (pkgs) stdenv;

  counts = {
    faucets = 2;
    relays = 2;
  };

  allCount = counts.faucets + counts.relays;
  allRange = range 1 allCount;

  jq = "${pkgs.jq}/bin/jq";
  curl = "${pkgs.curl}/bin/curl";

  listenPortFor = n: 3000 + n + n;
  restPortFor = n: 3001 + n + n;

  mkJormungandr = kind: n:
    { config, ... }:
    let
      listenPort = listenPortFor n;
      restPort = restPortFor n;
      secret = ./static/secrets + "/secret_pool_${toString n}.yaml";
      trustedPeers = take 5 (map (m:
        "/ip4/${config.networking.primaryIPAddress}/tcp/${
          toString (listenPortFor m)
        }") (filter (m: m != n) (range 1 counts.faucets)));
    in {
      system.activationScripts = optionalAttrs (kind == "faucet") {
        "copyJormungandrSecrets${toString n}" =
          optionalString (secret != null) ''
            mkdir -p /var/lib/keys
            cp ${secret} /var/lib/keys/jormungandr-pool-secret.yaml
          '';
      };

      systemd.services."jormungandr@${toString n}" =
        __trace "Make ${kind} node ${toString n}" {
          description = "Jormungandr node service %i";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            DynamicUser = true;
            User = "jormungandr%i";
            RestartSec = "${toString n}s";
            StartLimitBurst = 120;
            StartLimitIntervalSec = 120;
            Restart = "always";
            WorkingDirectory = "/var/lib/jormungandr${toString n}";
            StateDirectory = "jormungandr${toString n}";
          };

          environment.RUST_BACKTRACE = "full";
          environment.LISTEN_PORT = "$((3000 + %i))";

          serviceConfig.PermissionsStartOnly = true;
          preStart = ''
            if [ -f /var/lib/keys/jormungandr-pool-secret.yaml ]; then
              cp /var/lib/keys/jormungandr-pool-secret.yaml /var/lib/jormungandr${
                toString n
              }
              chmod 0600 /var/lib/jormungandr${toString n}/*
            fi
          '';

          script = let
            configJson = builtins.toFile "config.yaml" (builtins.toJSON {
              storage = "/var/lib/jormungandr${toString n}";

              explorer.enabled = false;

              log = {
                level = "info";
                format = "plain";
                output = "stderr";
              };

              rest.listen =
                "${config.networking.primaryIPAddress}:${toString restPort}";

              p2p = {
                public_address =
                  "/ip4/${config.networking.primaryIPAddress}/tcp/${
                    toString listenPort
                  }";

                topics_of_interest = {
                  messages = "low";
                  blocks = "normal";
                };

                listen_address =
                  "/ip4/${config.networking.primaryIPAddress}/tcp/${
                    toString listenPort
                  }";

                trusted_peers = trustedPeers;
              };
            });

            secretsArgs = concatStringsSep " " (optionals (kind == "faucet")
              (map (p: ''--secret "${p}"'')
                [ "/var/lib/keys/jormungandr-pool-secret.yaml" ]));

            genesisBlock = optionalString (kind == "faucet")
              "--genesis-block ${./static/block-0.bin}";

            genesisHash = stdenv.mkDerivation {
              name = "genesis-block";
              src = ./static/block-0.bin;
              unpackPhase = "true";
              installPhase =
                "${rust-packages.pkgs.jormungandr-cli}/bin/jcli genesis hash --input $src > $out";
            };

            genesisBlockHash = optionalString (kind == "relay")
              "--genesis-block-hash $(< ${genesisHash})";

            command = concatStringsSep " " (filter (s: s != "") [
              "${rust-packages.pkgs.jormungandr}/bin/jormungandr"
              genesisBlock
              genesisBlockHash
              secretsArgs
            ]);
          in ''
            set -ex
            ${command} --config ${configJson}
          '';
        };
    };

  mkFaucetNodes = from: to: args:
    foldl' (s: i: recursiveUpdate s (mkJormungandr "faucet" i args)) { }
    (range from to);

  mkRelayNodes = from: to: args:
    foldl' (s: i: recursiveUpdate s (mkJormungandr "relay" i args)) { }
    (range from to);

  allPorts =
    flatten (map (n: [ (listenPortFor n) (restPortFor n) ]) (range 1 allCount));

  testApiAddr = nodes:
    "${nodes.cluster.config.networking.primaryIPAddress}:${
      toString (restPortFor 1)
    }";

in import <nixpkgs/nixos/tests/make-test.nix> ({ pkgs, ... }: {
  name = "jormungandr-large";

  nodes = {
    cluster = args:
      (foldl' (all: nodes: recursiveUpdate all nodes) {} [
        (mkFaucetNodes 1 counts.faucets args)
        (mkRelayNodes (counts.faucets + 1) allCount args)
      ]) // {
        virtualisation.memorySize = 8000;
        networking.firewall.allowedTCPPorts = allPorts;
        environment.systemPackages = [ pkgs.tree pkgs.busybox pkgs.lsof ];
      };
  };

  testScript = { nodes, ... }: ''
    startAll;
    $cluster-sleep(60);
    print($cluster->execute("${curl} -s ${testApiAddr nodes}/api/v0/node/stats | ${jq}"));
  '';
})
