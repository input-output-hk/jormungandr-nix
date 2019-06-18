with import ../lib.nix;

let
  snapPackage = rustPkgs.callPackage ./. { inherit makeSnap; };
  shell = pkgs.stdenv.mkDerivation {
    name = "snapcraft-shell";
    buildInputs = with pkgs; [ snapcraft squashfsTools ];
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
