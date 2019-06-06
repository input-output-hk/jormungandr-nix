{ sigKey
, vrfKey
, nodeId
}:
builtins.toJSON {
  "genesis" = {
    sig_key = sigKey;
    vrf_key = vrfKey;
    node_id = nodeId;
  };
}
