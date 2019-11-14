let
  commonLib = import ./lib.nix;
  in with commonLib.lib; with import ./lib.nix;
{ package ? pkgs.jormungandr
, environment ? "beta"
, jcli ? pkgs.jormungandr-cli
, color ? true
, staking ? false
, sendLogs ? false
, genesisHash ? null
, trustedPeers ? null
, topicsOfInterest ? null
, customConfig ? {}
, ...
}@args:
let
  genesisHash' = genesisHash;
  trustedPeers' = trustedPeers;
in let
  customArgs = args // customConfig;
  genesisHash = if (genesisHash' == null) then commonLib.environments.${customArgs.environment}.genesisHash else genesisHash';
  trustedPeers = if (trustedPeers' == null) then commonLib.environments.${customArgs.environment}.trustedPeers else trustedPeers';
  niv = (import sources.niv {}).niv;
  scripts = pkgs.callPackage ./nix/scripts.nix ({
    inherit package jcli color staking sendLogs genesisHash trustedPeers
      topicsOfInterest niv;
  } // customArgs);
  explorerFrontend = (import ./explorer-frontend).jormungandr-explorer;
in {
  inherit niv sources explorerFrontend scripts genesisHash customConfig customArgs;
  inherit (scripts) shells;
}
