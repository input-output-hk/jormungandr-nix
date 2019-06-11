#!/usr/bin/env bash

sudo mkdir -p /etc/nix

cat <<EOF | sudo tee /etc/nix/nix.conf
sandbox = false
use-sqlite-wal = false
EOF

curl https://nixos.org/nix/install | sh
