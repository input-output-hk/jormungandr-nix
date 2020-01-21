let
  sources = import ../nix/sources.nix;
  pkgs = import sources.nixpkgs-crystal { };
in pkgs.crystal.buildCrystalPackage {
  name = "reward-api";
  version = "0.1.0";
  src = builtins.path { name = "reward-api-src"; path = ./.; };
  shardsFile = ./shards.nix;
  crystalBinaries.reward-api.src = "./src/reward-api.cr";
}
