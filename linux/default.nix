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
    apps.jormungandr = {
      command = "${jormungandr}/bin/jormungandr";
      plugs = [ "network" "network-bind" ];
    };
    apps.jcli = {
      command = "${jormungandr-cli}/bin/jcli";
      plugs = [ "network" "network-bind" ];
    };
    apps.bootstrap = {
      command = "${jormungandr-bootstrap}/bin/bootstrap";
      plugs = [ "network" "network-bind" ];
    };
  };
}
