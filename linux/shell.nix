with import ../lib.nix;

let
  jormungandr-bootstrap = (pkgs.callPackage ../. {
    rootDir = "$SNAP_USER_DATA";
  }).jormungandr-bootstrap;
  snapPackage = pkgs.callPackage ./. { inherit makeSnap jormungandr-bootstrap; };
  shell = pkgs.stdenv.mkDerivation {
    name = "snapcraft-shell";
    buildInputs = with pkgs; [ snapcraft squashfsTools xdelta ];
    shellHook = ''
    echo "Starting snapcraft development shell..."
    echo "snapPackage can be found at ${snapPackage}"
    '';
  };
  release = shell.overrideAttrs (oldAttrs: {
    name = "snapcraft-release";
    shellHook = ''
    echo "Creating and pushing snapcraft package..."
    snapcraft push --release=stable ${snapPackage}
    exit
    '';
  });
  passthru = shell;

in shell // { inherit release; }
