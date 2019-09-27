{ customConfig ? {}
}:
let
  default = import ./. { inherit customConfig; };

in default.shells.testnet // default.shells // {
  inherit (default) scripts;
}
