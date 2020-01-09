import csv
import json
import glob
import os
import bech32
import binascii
import time
from flask import Flask, request, abort
from watchdog.observers import Observer
from watchdog.events import PatternMatchingEventHandler

rewards_path = os.getenv("JORMUNGANDR_REWARD_DUMP_DIRECTORY","./rewards")
csvFilePath = 'reward-info-*'
rewards = {}

def create_app():
    app = Flask(__name__)

    @app.route('/api/rewards/<epoch>')
    def rewards_epoch(epoch):
        if epoch in rewards:
            return json.dumps(rewards[epoch])
        else:
            abort(404, description=f"No rewards found for epoch {epoch}")

    return app

def parseEpochRewards(file_name, epoch):
    pools = []
    accounts = []
    with open(file_name) as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        f.close()
    pools = {}
    poolsCount = 0
    accountsCount = 0
    accounts = {}
    for item in rows:
        recv = item['received']
        jtype = item['type']
        ident = item['identifier']
        record = epoch + ": " + recv
        if jtype == "drawn":
            drawn = int(item["distributed"])
        elif jtype == "fees":
            fees = int(item["distributed"])
        elif jtype == "treasury":
            treasury = int(item["received"])
        elif jtype == "pool":
            pools[ident] = { "received": int(recv), "distributed": int(item["distributed"]) }
        elif jtype == "account":
            addr = str(convertHexPubKey(ident))
            accounts[addr] = int(recv)
    return { "pools": pools, "accounts": accounts, "drawn": drawn, "treasury": treasury, "fees": fees }

def convertHexPubKey(hex_pub_key, output_format="ed25519"):
    raw_pub_key = binascii.unhexlify(hex_pub_key)
    bech32_pub_key = bech32.bech32_encode("ed25519_pk", bech32.convertbits(raw_pub_key, 8, 5))
    if output_format == "ed25519":
        return bech32_pub_key
    elif output_format == "jcliaddr":
        return "jcliaddr_" + hex_pub_key
    else:
        print(f"output format {output_format} not supported!")



# parse all reward export csv files in order of time created
os.chdir(os.getcwd() + "/" + rewards_path)
files = glob.glob(csvFilePath)
files.sort(key=os.path.getmtime)
for filename in files:
    csvfile = os.path.splitext(filename)[0]
    _, _, epoch, _ = filename.split('-')
    rewards[epoch] = parseEpochRewards(csvfile, epoch)
    print(f"parsed epoch {epoch}")

# setup an observer to parse new files

parse_event_handler = PatternMatchingEventHandler(csvFilePath, "", True, True)

def parseFileEvent(event):
    filename = event.src_path
    csvfile = os.path.splitext(filename)[0]
    _, _, epoch, _ = filename.split('-')
    rewards[epoch] = parseEpochRewards(csvfile, epoch)
    print(f"parsed epoch {epoch}")

parse_event_handler.on_created = parseFileEvent
parse_event_handler.on_modified = parseFileEvent

file_observer  = Observer()
file_observer.schedule(parse_event_handler, "./", recursive=False)

file_observer.start()

# start the rest api
app = create_app()
