{ ... }@args:
let
  default = import ./. args;

in default.shells.testnet // default.shells
