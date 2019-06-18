with import ./lib.nix; with lib;
{
  snapPackage = rustPkgs.callPackage ./linux { inherit makeSnap; };
}
