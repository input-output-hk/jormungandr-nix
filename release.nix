{ supportedSystems ? [ "x86_64-linux" "x86_64-darwin" ]
, supportedCrossSystems ? [ "x86_64-linux" ]
, scrubJobs ? true
, jormungandr ? { outPath = ./.; rev = "abcdef"; }
, projectArgs ? { config = { allowUnfree = false; inHydra = true; }; }
}:
let
  commonLib = import ./lib.nix;
  pkgs = commonLib.pkgs;
in


with (import commonLib.iohkNix.release-lib {
  inherit supportedSystems supportedCrossSystems scrubJobs projectArgs pkgs;
  packageSet = import jormungandr;
  gitrev = jormungandr.rev;
});

with pkgs.lib;

let

  # TODO: add CI jobs here for jormungandr-nix
  jobs = {
  } // (mkRequiredJob ([
    ]));
in jobs
