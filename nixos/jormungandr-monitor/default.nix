{ python3, makeWrapper, runCommand, jormungandr-cli, lsof, coreutils }:

let
  python = python3.withPackages (ps: with ps; [ prometheus_client dateutil ]);
in runCommand "jormungandr-monitor" {
  buildInputs = [ python makeWrapper ];
  jcli = "${jormungandr-cli}/bin/jcli";
  lsof = "${lsof}/bin/lsof";
  wc = "${coreutils}/bin/wc";
} ''
  substituteAll ${./monitor.py} $out
  chmod +x $out
  patchShebangs $out
''
