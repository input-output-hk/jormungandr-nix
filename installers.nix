with import ./lib.nix; with lib;
let
  jormungandr-bootstrap = (pkgs.callPackage ./. {
    rootDir = "$SNAP_USER_DATA";
  }).jormungandr-bootstrap;
in {
  chocoPackage = pkgs.callPackage ./windows { inherit choco; };
  snapPackage = pkgs.callPackage ./linux { inherit makeSnap jormungandr-bootstrap; };
}
