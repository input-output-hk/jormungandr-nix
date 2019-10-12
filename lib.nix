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
  snapcraft = rustPkgs.callPackage ./nix/snapcraft.nix {};
  choco = iohkNix.pkgs.callPackage ./nix/choco.nix { inherit mono; };
  squashfsTools = rustPkgs.squashfsTools.overrideAttrs (old: {
    patches = old.patches ++ [
      ./nix/0005-add-fstime.patch
    ];
  });
  snapReviewTools = rustPkgs.callPackage ./nix/snap-review-tools.nix {
    inherit squashfsTools;
  };
  genesisHash = "adbdd5ede31637f6c9bad5c271eec0bc3d0cb9efb86a5b913bb55cba549d0770";
  trustedPeers = [
    "/ip4/3.123.177.192/tcp/3000"
    "/ip4/3.123.155.47/tcp/3000"
    "/ip4/52.57.157.167/tcp/3000"
    "/ip4/3.112.185.217/tcp/3000"
    "/ip4/18.140.134.230/tcp/3000"
    "/ip4/18.139.40.4/tcp/3000"
    "/ip4/3.115.57.216/tcp/3000"
  ];
  defaultJormungandrConfig = {
    log = {
      level = "info";
      format = "plain";
      output = "stderr";
    };
    rest = {
      listen = "127.0.0.1:3100";
    };
    p2p = {
      trusted_peers = trustedPeers;
      topics_of_interest = {
        messages = "low";
        blocks = "normal";
      };
    };
  };
in
rec {
  inherit sources iohkNix arionPkgs makeSnap snapcraft snapReviewTools squashfsTools choco genesisHash trustedPeers defaultJormungandrConfig;
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
