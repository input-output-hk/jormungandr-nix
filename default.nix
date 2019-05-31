# Imports the iohk-nix library.
# The version can be overridden for debugging purposes by setting
# NIX_PATH=iohk_nix=/path/to/iohk-nix
let
  localLib = import ./lib.nix;
  pkgs = localLib.pkgs;
  jormungandr = pkgs.jormungandr;
  setupStakePool = pkgs.callPackage ./nix/setup-stake-pool.nix {};
  makeGenesisFile = pkgs.callPackage ./nix/make-genesis.nix {};
in
{
  inherit jormungandr setupStakePool makeGenesisFile;
  inherit (localLib) iohkNix;
}
