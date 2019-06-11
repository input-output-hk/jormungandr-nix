#!/usr/bin/env bash

sudo mkdir -p /etc/nix

cat <<EOF | sudo tee /etc/nix/nix.conf
sandbox = false
use-sqlite-wal = false
substituters = https://cache.nixos.org https://hydra.iohk.io
trusted-substituters =
trusted-public-keys = hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
EOF

curl https://nixos.org/nix/install | sh
