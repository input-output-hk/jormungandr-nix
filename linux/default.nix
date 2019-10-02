{
  makeSnap
, jormungandr
, jormungandr-cli
, scripts
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
    apps.run = {
      command = "${scripts.runJormungandrSnappy}/bin/run";
      plugs = [ "network" "network-bind" ];
    };
    apps.create-stake-pool = {
      command = "${scripts.createStakePool}/bin/create-stake-pool";
    };
    apps.delegate-stake = {
      command = "${scripts.delegateStake}/bin/delegate-stake";
    };
    apps.send-funds = {
      command = "${scripts.sendFunds}/bin/send-funds";
      plugs = [ "network" "network-bind" ];
    };
    apps.send-certificate = {
      command = "${scripts.sendCertificate}/bin/send-certificate";
      plugs = [ "network" "network-bind" ];
    };
  };
}
