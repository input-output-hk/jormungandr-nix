with import ./nix {};
mkShell {
  buildInputs = [
    niv
    yarn
    yarn2nix
  ];
}
