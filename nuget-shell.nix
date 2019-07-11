with import ./lib.nix; with lib;

iohkNix.pkgs.stdenv.mkDerivation {
  name = "nuget-shell";
  buildInputs = [ iohkNix.pkgs.dotnetPackages.Nuget ];
  shellHook = ''
    echo "####"
    echo "#### Chocolatey package push via:"
    echo "####   nuget push -ApiKey \$CHOCOKEY -Source https://push.chocolatey.org \$NUPKGFILE -Verbosity detailed"
    echo "####"
  '';
}
