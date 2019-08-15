# Imports the iohk-nix library.
# The version can be overridden for debugging purposes by setting
# NIX_PATH=iohk_nix=/path/to/iohk-nix
let
  iohkNixSrc = 
    let try = builtins.tryEval <iohk_nix>;
    in if try.success
    then builtins.trace "using host <iohk_nix>" try.value
    else
      let
        spec = builtins.fromJSON (builtins.readFile ./nix/iohk-nix-src.json);
      in builtins.fetchTarball {
        url = "${spec.url}/archive/${spec.rev}.tar.gz";
        inherit (spec) sha256;
      };
  iohkNix = import iohkNixSrc { nixpkgsJsonOverride = ./nix/nixpkgs-src.json; };
  arionPkgs = import (let
      spec = builtins.fromJSON (builtins.readFile ./nix/arion-src.json);
    in builtins.fetchTarball {
      url = "${spec.url}/archive/${spec.rev}.tar.gz";
      inherit (spec) sha256;
    }) {};

  oldNixpkgsSrc =
    let
      spec = builtins.fromJSON (builtins.readFile ./nix/nixpkgs-src-mono.json);
    in builtins.fetchTarball {
      url = "${spec.url}/archive/${spec.rev}.tar.gz";
      inherit (spec) sha256;
    };

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
  inherit iohkNix arionPkgs makeSnap snapcraft snapReviewTools squashfsTools choco;
  pkgs = (rustPkgs.extend (self: super: {
    uuidgen = if self.stdenv.isLinux
      then super.runCommand "uuidgen" {} ''
        mkdir $out/bin -pv
        cp -v ${super.utillinuxMinimal}/bin/uuidgen $out/bin/uuidgen
      ''
      else super.runCommand "uuidgen" {} ''
        mkdir $out/bin -pv
        ln -sv /usr/bin/uuidgen $out/bin/uuidgen
      '';
  })).extend (import (iohkNixSrc + "/overlays/cardano"));
  inherit (pkgs) lib;
}
