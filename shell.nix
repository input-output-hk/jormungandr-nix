let
  myPkgs = import ./.;
  pkgs = myPkgs.iohkNix.rust-packages.pkgs;
in pkgs.stdenv.mkDerivation {
  name = "jormungandr-demo";
  buildInputs = with pkgs; [
    jormungandr
  ];
  shellHook = ''
  echo "Jormungandr Demo" \
  | ${pkgs.figlet}/bin/figlet -f banner -c \
  | ${pkgs.lolcat}/bin/lolcat
  cat <<EOF
  Instructions for Starting one-node genesis cluster:
  EOF
  '';
}
