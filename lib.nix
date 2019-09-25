# Imports the iohk-nix library.
# The version can be overridden for debugging purposes by setting
# NIX_PATH=iohk_nix=/path/to/iohk-nix
let
  sources = import ./nix/sources.nix;
  iohkNix = import sources.iohk-nix { nixpkgsOverride = sources.nixpkgs; };
  arionPkgs = import sources.arion {};

  oldNixpkgsSrc = sources.nixpkgs-mono;

  oldNixpkgs = import oldNixpkgsSrc {};
  mono = (oldNixpkgs.pkgs.callPackage (oldNixpkgsSrc + "/pkgs/development/compilers/mono/default.nix") {
    withLLVM = false;
  });
  rustPkgs = iohkNix.rust-packages.pkgs;
  makeSnap = rustPkgs.callPackage ./nix/make-snap.nix {};
  snapcraft = iohkNix.pkgs.callPackage ./nix/snapcraft.nix {};
  choco = iohkNix.pkgs.callPackage ./nix/choco.nix { inherit mono; };
  squashfsTools = rustPkgs.squashfsTools.overrideAttrs (old: {
    patches = old.patches ++ [
      ./nix/0005-add-fstime.patch
    ];
  });
  snapReviewTools = rustPkgs.callPackage ./nix/snap-review-tools.nix {
    inherit squashfsTools;
  };
in
rec {
  inherit sources iohkNix arionPkgs makeSnap snapcraft snapReviewTools squashfsTools choco;
  pkgs = rustPkgs.extend (self: super: {
    uuidgen = if self.stdenv.isLinux
      then super.runCommand "uuidgen" {} ''
        mkdir $out/bin -pv
        cp -v ${super.utillinuxMinimal}/bin/uuidgen $out/bin/uuidgen
      ''
      else super.runCommand "uuidgen" {} ''
        mkdir $out/bin -pv
        ln -sv /usr/bin/uuidgen $out/bin/uuidgen
      '';
  });
  inherit (pkgs) lib;
}
