{
  makeSnap
, jormungandr
, jormungandr-cli
, jormungandr-bootstrap
}:

makeSnap {
  meta = {
    name = "jormungandr";
    summary = "jormungandr";
    description = "jormungandr node for cardano";
    architectures = [ "amd64" ];
    confinement = "strict";
    apps.jormungandr.command = "${jormungandr}/bin/jormungandr";
    apps.jcli.command = "${jormungandr-cli}/bin/jcli";
    apps.bootstrap.command = jormungandr-bootstrap;
  };
}
