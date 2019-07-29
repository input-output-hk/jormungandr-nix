{ chocoSignedZip ? null }:

with import ./lib.nix; with lib;
let
  jormungandr-bootstrap = (pkgs.callPackage ./. {
    rootDir = "$SNAP_USER_DATA";
  }).jormungandr-bootstrap;

  # Allow a chocolatey override for a local signed binaries zipfile
  chocoReleaseOverride = if (chocoSignedZip != null)
    then (./. + chocoSignedZip)
    else null;
in {
  chocoPackage = pkgs.callPackage ./windows { inherit choco chocoReleaseOverride; };
  snapPackage = pkgs.callPackage ./linux { inherit makeSnap jormungandr-bootstrap; };
}
