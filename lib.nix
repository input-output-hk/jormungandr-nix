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
      {
        address = "/ip4/3.115.194.22/tcp/3000";
        id = "ed25519_pk1npsal4j9p9nlfs0fsmfjyga9uqk5gcslyuvxy6pexxr0j34j83rsf98wl2";
      }
      {
        address = "/ip4/13.113.10.64/tcp/3000";
        id = "ed25519_pk16pw2st5wgx4558c6temj8tzv0pqc37qqjpy53fstdyzwxaypveys3qcpfl";
      }
      {
        address = "/ip4/52.57.214.174/tcp/3000";
        id = "ed25519_pk1v4cj0edgmp8f2m5gex85jglrs2ruvu4z7xgy8fvhr0ma2lmyhtyszxtejz";
      }
      {
        address = "/ip4/3.120.96.93/tcp/3000";
        id = "ed25519_pk10gmg0zkxpuzkghxc39n3a646pdru6xc24rch987cgw7zq5pmytmszjdmvh";
      }
      {
        address = "/ip4/52.28.134.8/tcp/3000";
        id = "ed25519_pk1unu66eej6h6uxv4j4e9crfarnm6jknmtx9eknvq5vzsqpq6a9vxqr78xrw";
      }
      {
        address = "/ip4/13.52.208.132/tcp/3000";
        id = "ed25519_pk15ppd5xlg6tylamskqkxh4rzum26w9acph8gzg86w4dd9a88qpjms26g5q9";
      }
      {
        address = "/ip4/54.153.19.202/tcp/3000";
        id = "ed25519_pk1j9nj2u0amlg28k27pw24hre0vtyp3ge0xhq6h9mxwqeur48u463s0crpfk";
      }
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
} // iohkNix.jormungandrLib
