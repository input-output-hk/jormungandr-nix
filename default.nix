let
  commonLib = import ./lib.nix;
  in with commonLib.lib; with import ./lib.nix;
{ package ? pkgs.jormungandr
, jcli ? pkgs.jormungandr-cli
, color ? true
, staking ? false
, sendLogs ? false
, genesisHash ? "adbdd5ede31637f6c9bad5c271eec0bc3d0cb9efb86a5b913bb55cba549d0770"
, trustedPeers ? [
    "/ip4/3.123.177.192/tcp/3000"
    "/ip4/3.123.155.47/tcp/3000"
    "/ip4/52.57.157.167/tcp/3000"
    "/ip4/3.112.185.217/tcp/3000"
    "/ip4/18.140.134.230/tcp/3000"
    "/ip4/18.139.40.4/tcp/3000"
    "/ip4/3.115.57.216/tcp/3000"
  ]
, topicsOfInterest ? null
, ...
}@args:
let
  niv = (import sources.niv {}).niv;
  scripts = pkgs.callPackage ./nix/scripts.nix ({
    inherit package jcli color staking sendLogs genesisHash trustedPeers
      topicsOfInterest niv;
  } // args);
in {
  inherit niv sources;
  inherit (scripts) shells;
  inherit scripts;
}
