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
csvFilePath = './reward-info-*'
rewards = {}

rewards_total = {}

def create_app():
    app = Flask(__name__)

    @app.route('/api/rewards/<epoch>')
    def rewards_epoch(epoch):
        if epoch in rewards:
            return json.dumps(rewards[epoch])
        else:
            abort(404, description=f"No rewards found for epoch {epoch}")
    @app.route('/api/rewards/total')
    def rewards_total_api():
        return json.dumps(rewards_total)

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
    update_totals()
    return { "pools": pools, "accounts": accounts, "drawn": drawn, "treasury": treasury, "fees": fees }

def update_totals():
    global rewards_total
    rewards_total = {}
    rewards_total["pools"] = {}
    rewards_total["accounts"] = {}
    rewards_total["drawn"] = 0
    rewards_total["treasury"] = 0
    rewards_total["fees"] = 0
    for epoch,epoch_data in rewards.items():
        for pool,pool_data in epoch_data["pools"].items():
            if pool not in rewards_total["pools"]:
                rewards_total["pools"][pool] = { "received": 0, "distributed": 0 }
            rewards_total["pools"][pool]["received"] = rewards_total["pools"][pool]["received"] + pool_data["received"]
            rewards_total["pools"][pool]["distributed"] = rewards_total["pools"][pool]["distributed"] + pool_data["distributed"]
        for account,value in epoch_data["accounts"].items():
            if account not in rewards_total["accounts"]:
                rewards_total["accounts"][account] = value
            else:
                rewards_total["accounts"][account] = rewards_total["accounts"][account] + value
        rewards_total["drawn"] = rewards_total["drawn"] + epoch_data["drawn"]
        rewards_total["treasury"] = rewards_total["treasury"] + epoch_data["treasury"]
        rewards_total["fees"] = rewards_total["fees"] + epoch_data["fees"]

def convertHexPubKey(hex_pub_key, output_format="ed25519"):
    raw_pub_key = binascii.unhexlify(hex_pub_key)
    bech32_pub_key = bech32.bech32_encode("ed25519_pk", bech32.convertbits(raw_pub_key, 8, 5))
    if output_format == "ed25519":
        return bech32_pub_key
    elif output_format == "jcliaddr":
        return "jcliaddr_" + hex_pub_key
    else:
        print(f"output format {output_format} not supported!")

os.chdir(os.getcwd() + "/" + rewards_path)

# setup an observer to parse new files

parse_event_handler = PatternMatchingEventHandler(patterns=[csvFilePath])

def parseFileEvent(event):
    print(event)
    filename = event.src_path
    csvfile = os.path.splitext(filename)[0]
    _, _, epoch, _ = filename.split('-')
    rewards[epoch] = parseEpochRewards(csvfile, epoch)
    print(f"(watchdog): parsed epoch {epoch}")

parse_event_handler.on_created = parseFileEvent
parse_event_handler.on_modified = parseFileEvent

file_observer  = Observer()
file_observer.schedule(parse_event_handler, "./", recursive=False)

file_observer.start()

# parse all reward export csv files in order of time created
files = glob.glob(csvFilePath)
files.sort(key=os.path.getmtime)
for filename in files:
    csvfile = os.path.splitext(filename)[0]
    _, _, epoch, _ = filename.split('-')
    rewards[epoch] = parseEpochRewards(csvfile, epoch)
    print(f"(initial startup): parsed epoch {epoch}")


# start the rest api
app = create_app()
