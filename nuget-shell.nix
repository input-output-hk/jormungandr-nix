with import ./lib.nix; with lib;

iohkNix.pkgs.stdenv.mkDerivation {
  name = "nuget-shell";
  buildInputs = [ iohkNix.pkgs.dotnetPackages.Nuget ];
  shellHook = ''
    export MONO_TLS_PROVIDER=legacy
    export TERM=xterm
    echo "####"
    echo "#### Chocolatey package push via:"
    echo "####   nuget push -ApiKey \$CHOCOKEY -Source https://push.chocolatey.org \$NUPKGFILE -Verbosity detailed"
    echo "####"
  '';
}
