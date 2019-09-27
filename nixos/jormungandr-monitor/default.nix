{ python3, makeWrapper, runCommand }:

let
  python = python3.withPackages (ps: with ps; [ prometheus_client dateutil ]);
  inherit ((import ../../lib.nix).pkgs) jormungandr-cli;
in runCommand "jormungandr-monitor" {
  buildInputs = [ python makeWrapper ];
  jcli = "${jormungandr-cli}/bin/jcli";
} ''
  substituteAll ${./monitor.py} $out
  chmod +x $out
  patchShebangs $out
''
