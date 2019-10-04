#!/usr/bin/env nix-shell
#!nix-shell -p python3Packages.ipython python3Packages.requests -i python3

import requests
import os
import binascii
import json

api_url_base = os.environ.get("JORMUNGANDR_RESTAPI_URL", "http://localhost:3001/api")
api_url = f"{api_url_base}/v0"

def get_api(path):
    resp = requests.get(url = f"{api_url}/{path}")
    return resp.text

def get_tip():
    return get_api("tip")

def get_block(block_id):
    resp = requests.get(url = f"{api_url}/block/{block_id}")
    hex_block = resp.content.hex()
    return hex_block

def parse_block(block):
    return {
      "epoch": block[16:24],
      "slot": block[24:32],
      "parent": block[104:168],
      "pool": block[168:232],
    }

tip = get_tip()
block = parse_block(get_block(tip))

epochs = {}
pools = {}

while block["parent"] != "0000000000000000000000000000000000000000000000000000000000000000":
    epoch = block["epoch"]
    parent = block["parent"]
    pool = block["pool"]
    if epoch not in epochs:
        epochs[epoch] = {}
    if pool not in epochs[epoch]:
        epochs[epoch][pool] = 1
    else:
        epochs[epoch][pool] = epochs[epoch][pool] + 1
    block = parse_block(get_block(block["parent"]))

print(json.dumps(epochs))






#TIP=$(jcli rest v0 tip get)
#CURRENT=$TIP
#echo $TIP
#declare -A POOLS
#while [[ "$CURRENT" != "0000000000000000000000000000000000000000000000000000000000000000" ]]
#do
#  BLOCK=$(jcli rest v0 block $CURRENT get)
#  EPOCH=$((0x${BLOCK:16:8}))
#  SLOT=$((0x${BLOCK:24:8}))
#  NEXT=${BLOCK:104:64}
#  POOL=${BLOCK:168:64}
#  POOLS["${POOL}"]
#  CURRENT=$NEXT
#done
