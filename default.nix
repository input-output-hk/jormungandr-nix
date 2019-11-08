let
  commonLib = import ./lib.nix;
  in with commonLib.lib; with import ./lib.nix;
{ package ? pkgs.jormungandr
, jcli ? pkgs.jormungandr-cli
, color ? true
, staking ? false
, sendLogs ? false
, genesisHash ? commonLib.environments.nightly.genesisHash
, trustedPeers ? commonLib.environments.nightly.trustedPeers
, topicsOfInterest ? null
, customConfig ? {}
, ...
}@args:
let
  customArgs = args // customConfig;
  niv = (import sources.niv {}).niv;
  scripts = pkgs.callPackage ./nix/scripts.nix ({
    inherit package jcli color staking sendLogs genesisHash trustedPeers
      topicsOfInterest niv;
  } // customArgs);
  explorerFrontend = (import ./explorer-frontend).jormungandr-explorer;
in {
  inherit niv sources explorerFrontend;
  inherit (scripts) shells;
  inherit scripts;
}
