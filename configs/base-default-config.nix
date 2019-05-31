{
  storage = "/tmp/storage";
  logger = {
    verbosity = 1;
    format = "json";
  };
  peer_2_peer = {
    trusted_peers = [
      { id = 1;
        address = "/ip4/104.24.28.11/tcp/8299";
      }
      { id = 2;
        address = "/ip4/104.24.29.11/tcp/8299";
      }
    ];
    public_address = "/ip4/127.0.0.1/tcp/8080";
    topics_of_interests = {
      messages = "low";
      blocks = "normal";
    };
  };
}