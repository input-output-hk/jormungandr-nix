{ sources ? import ../../nix/sources.nix }:
with
  { overlay = self: super:
      { inherit (import sources.niv {}) niv;
        nodejs = super.nodejs-12_x;
        packages = self.callPackages ./packages.nix {};
        inherit (import sources.yarn2nix { pkgs = self; }) yarn2nix mkYarnPackage mkYarnModules;
        js-chain-libs = sources.js-chain-libs;
      };
  };
import sources.nixpkgs
  { overlays = [ overlay ] ; config = {}; }
