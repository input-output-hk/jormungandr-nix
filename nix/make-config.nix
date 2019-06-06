{ lib
, storage
, topicsOfInterests
, httpListen ? "127.0.0.1:8443"
, httpPrefix ? "api"
, loggerVerbosity ? 1
, loggerFormat ? "json"
, publicAddress ? "/ip4/127.0.0.1/tcp/8299"
, peerAddresses ? ""
, ...
}:
with lib; builtins.toJSON {
  storage = storage;
  logger = {
    verbosity = loggerVerbosity;
    format = loggerFormat;
  };
  rest = {
    listen = httpListen;
    prefix = httpPrefix;
  };
  peer_2_peer = {
    public_address = publicAddress;
    trusted_peers = if (peerAddresses == "") then [] else
      imap1 (i: a: { id = i; address = a; }) (splitString "," peerAddresses);
    topics_of_interests = listToAttrs (map (topic: 
      let
        split = splitString "=" topic;
      in
        nameValuePair (head split) (last split)
      ) (splitString "," topicsOfInterests));
  };
}

