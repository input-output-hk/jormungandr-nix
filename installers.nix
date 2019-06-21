with import ./lib.nix; with lib;
{
  chocoPackage = pkgs.callPackage ./windows {};
  snapPackage = rustPkgs.callPackage ./linux { inherit makeSnap; };
}
