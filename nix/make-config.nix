{ lib
, storage
, topics_of_interest
, rest_listen
, rest_prefix
, logger_level ? "info"
, logger_format ? "plain"
, logger_output ? "stderr"
, logger_backend ? "monitoring.stakepool.cardano-testnet.iohkdev.io:12201"
, public_address ? "/ip4/127.0.0.1/tcp/8299"
, trusted_peers ? ""
, logs_id
, ...
}:
with lib; builtins.toJSON {
  storage = storage;
  log = let
    output = if logger_output == "gelf" then {
      gelf = {
        backend = logger_backend;
        log_id = logs_id;
      };
    } else logger_output;
  in {
    level = logger_level;
    format = logger_format;
    output = output;
  };
  rest = {
    listen = rest_listen;
    prefix = rest_prefix;
  };
  p2p = {
    public_address = public_address;
    trusted_peers = if (trusted_peers == "") then [] else
      (splitString "," trusted_peers);
    topics_of_interest = listToAttrs (map (topic:
      let
        split = splitString "=" topic;
      in
        nameValuePair (head split) (last split)
      ) (splitString "," topics_of_interest));
  };
}

