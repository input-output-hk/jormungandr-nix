with import ../lib.nix;

{
  releaseType ? "edge"
}:

let
  scripts = (pkgs.callPackage ../. {
    rootDir = "$SNAP_USER_DATA";
  }).scripts;
  snapPackage = pkgs.callPackage ./. { inherit makeSnap scripts; };
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
    snapcraft push --release=${releaseType} ${snapPackage}
    exit
    '';
  });
  passthru = shell;

in shell // { inherit release; }
