{ lib
, storage
, topics_of_interests
, rest_listen
, rest_prefix
, logger_verbosity ? 1
, logger_format ? "json"
, public_address ? "/ip4/127.0.0.1/tcp/8299"
, trusted_peers ? ""
, ...
}:
with lib; builtins.toJSON {
  storage = storage;
  logger = {
    verbosity = logger_verbosity;
    format = logger_format;
  };
  rest = {
    listen = rest_listen;
    prefix = rest_prefix;
  };
  peer_2_peer = {
    public_address = public_address;
    trusted_peers = if (trusted_peers == "") then [] else
      imap1 (i: a: { id = i; address = a; }) (splitString "," trusted_peers);
    topics_of_interests = listToAttrs (map (topic: 
      let
        split = splitString "=" topic;
      in
        nameValuePair (head split) (last split)
      ) (splitString "," topics_of_interests));
  };
}

