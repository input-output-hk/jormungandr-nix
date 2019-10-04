{ sources ? import ../nix/sources.nix }:
with
  { overlay = _: pkgs:
      { inherit (import sources.niv {}) niv;
        packages = pkgs.callPackages ./packages.nix {};
        inherit (import sources.yarn2nix { inherit pkgs; }) yarn2nix mkYarnPackage mkYarnModules;
        js-chain-libs = sources.js-chain-libs;
      };
  };
import sources.nixpkgs
  { overlays = [ overlay ] ; config = {}; }
