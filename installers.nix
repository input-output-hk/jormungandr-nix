with import ./lib.nix; with lib;
let
  jormungandr-bootstrap = (pkgs.callPackage ./. {
  }).jormungandr-bootstrap;
in {
  chocoPackage = pkgs.callPackage ./windows {};
  snapPackage = pkgs.callPackage ./linux { inherit makeSnap jormungandr-bootstrap; };
}
