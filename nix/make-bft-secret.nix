{ sigKey }:
builtins.toJSON {
  "bft" = {
    signing_key = sigKey;
  };
}
