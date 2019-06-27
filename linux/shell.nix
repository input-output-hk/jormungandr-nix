with import ../lib.nix;

let
  jormungandr-bootstrap = (pkgs.callPackage ../. {
    rootDir = "$SNAP_USER_DATA";
  }).jormungandr-bootstrap;
  snapPackage = pkgs.callPackage ./. { inherit makeSnap jormungandr-bootstrap; };
  shell = pkgs.stdenv.mkDerivation {
    name = "snapcraft-shell";
    buildInputs = with pkgs; [ snapcraft squashfsTools xdelta snapReviewTools ];
    shellHook = ''
    echo "Starting snapcraft development shell..."
    echo "snapPackage can be found at ${snapPackage}"
    '';
  };
  release = shell.overrideAttrs (oldAttrs: {
    name = "snapcraft-release";
    shellHook = ''
    echo "Checking that snapcraft package passes tests"
    set -e
    snap-review ${snapPackage}

    echo "Creating and pushing snapcraft package..."
    snapcraft push --release=stable ${snapPackage}
    exit
    '';
  });
  passthru = shell;

in shell // { inherit release; }
