{
  makeSnap
, jormungandr
}:

makeSnap {
  meta = {
    name = "jormungandr";
    summary = "jormungandr";
    description = "jormungandr";
    architectures = [ "amd64" ];
    confinement = "strict";
    apps.jormungandr.command = "${jormungandr}/bin/jormungandr";
    apps.jcli.command = "${jormungandr}/bin/jcli";
  };
}
