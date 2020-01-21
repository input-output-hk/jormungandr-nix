let
  commonLib = import ./lib.nix;
  in with commonLib.lib; with import ./lib.nix;
{ environment ? "itn_rewards_v1"
, versionOverride ? null
, color ? true
, staking ? false
, sendLogs ? false
, genesisHash ? null
, trustedPeers ? null
, topicsOfInterest ? null
, customConfig ? {}
, rewardsLog ? false
, enableWallet ? false
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
  cardanoWallet = (import sources.cardano-wallet { gitrev = sources.cardano-wallet.rev; }).cardano-wallet-jormungandr;
  scripts = pkgs.callPackage ./nix/scripts.nix ({
    inherit packages color staking sendLogs genesisHash trustedPeers
      topicsOfInterest niv cardanoWallet reward-api;
  } // customArgs);
  explorerFrontend = (import ./explorer-frontend).jormungandr-explorer;
in {
  inherit niv sources explorerFrontend scripts reward-api;
  inherit (scripts) shells;
}
