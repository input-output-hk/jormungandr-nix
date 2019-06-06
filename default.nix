{...}@args:
# Imports the iohk-nix library.
# The version can be overridden for debugging purposes by setting
# NIX_PATH=iohk_nix=/path/to/iohk-nix
with import ./lib.nix;
let
  setupStakePool = rustPkgs.callPackage ./nix/setup-stake-pool.nix args;
in
{
  inherit iohkNix jormungandr setupStakePool block0 config;
}
