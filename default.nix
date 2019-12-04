let
  commonLib = import ./lib.nix;
  in with commonLib.lib; with import ./lib.nix;
{ environment ? "beta"
, versionOverride ? null
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
  defaultArgs = {
    inherit environment color staking sendLogs genesisHash trustedPeers topicsOfInterest versionOverride;
    packages = if (customArgs.versionOverride == null) then commonLib.environments.${customArgs.environment}.packages else commonLib.packages.${customArgs.versionOverride};
  };
  customArgs = defaultArgs // args // customConfig;
  genesisHash = if (genesisHash' == null) then commonLib.environments.${customArgs.environment}.genesisHash else genesisHash';
  trustedPeers = if (trustedPeers' == null) then commonLib.environments.${customArgs.environment}.trustedPeers else trustedPeers';
  niv = (import sources.niv {}).niv;
  scripts = pkgs.callPackage ./nix/scripts.nix ({
    inherit packages color staking sendLogs genesisHash trustedPeers
      topicsOfInterest niv;
  } // customArgs);
  explorerFrontend = (import ./explorer-frontend).jormungandr-explorer;
in {
  inherit niv sources explorerFrontend scripts;
  inherit (scripts) shells;
}
