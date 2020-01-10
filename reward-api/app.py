import csv
import json
import glob
import os
import bech32
import binascii
import time
import requests
from requests.exceptions import HTTPError
from flask import Flask, request, abort
from watchdog.observers import Observer
from watchdog.events import PatternMatchingEventHandler

rewards_path = os.getenv("JORMUNGANDR_REWARD_DUMP_DIRECTORY","./rewards")
csvFilePath = './reward-info-*'
rewards = {}

rewards_total = {}

api_url_base = os.environ.get("JORMUNGANDR_RESTAPI_URL", "http://localhost:3001/api")
api_url = f"{api_url_base}/v0"

def endpoint(url):
    try:
        r = requests.get(url)
        r.raise_for_status()
    except HTTPError as http_err:
        print("\nWeb API unavailable.\nError Details:\n")
        print(f"HTTP error occurred: {http_err}")
        exit(1)
    except Exception as err:
        print("\nWeb API unavailable.\nError Details:\n")
        print(f"Other error occurred: {err}")
        exit(1)
    else:
        return(r)

def get_api(path):
    r = endpoint(f'{api_url}/{path}')
    return r.text


def get_tip():
    return get_api("tip")


def get_block(block_id):
    r = endpoint(f'{api_url}/block/{block_id}')
    hex_block = r.content.hex()
    return hex_block

def find_block_epoch(epoch):
    current_block = parse_block(get_block(get_tip()))
    while int(current_block["epoch"]) > int(epoch):
        current_block = parse_block(get_block(current_block["parent"]))
    if current_block["epoch"] == int(epoch):
        print(current_block["epoch"])
        return current_block
    print("could not find block")
    return None

def count_pool_blocks_epoch(epoch):
    print(f"counting blocks for epoch {epoch}")
    global rewards
    current_block = find_block_epoch(epoch)
    while current_block["epoch"] == epoch:
        current_block_epoch = current_block["epoch"]
        current_block_pool = current_block["pool"]
        if current_block_epoch in rewards:
            if current_block_pool in rewards[current_block_epoch]["pools"]:
                if "block_count" in rewards[current_block_epoch]["pools"][current_block_pool]:
                    rewards[current_block_epoch]["pools"][current_block_pool]["block_count"] = rewards[current_block_epoch]["pools"][current_block_pool]["block_count"] + 1
                else:
                    rewards[current_block_epoch]["pools"][current_block_pool]["block_count"] = 1
            else:
                print(f"pool {current_block_pool} received no rewards but created a block in epoch {current_block_epoch}!")
                rewards[current_block_epoch]["pools"][current_block_pool] = { "block_count": 1, "received": 0, "distributed": 0 }
        current_block = parse_block(get_block(current_block["parent"]))

def count_pool_blocks_all():
    global rewards
    current_block_hash = get_tip()
    current_block = parse_block(get_block(current_block_hash))
    while current_block["parent"] != ("0" * 64):
        current_block_epoch = str(current_block["epoch"])
        current_block_pool = current_block["pool"]
        if current_block_epoch in rewards:
            if current_block_pool in rewards[current_block_epoch]["pools"]:
                if "block_count" in rewards[current_block_epoch]["pools"][current_block_pool]:
                    rewards[current_block_epoch]["pools"][current_block_pool]["block_count"] = rewards[current_block_epoch]["pools"][current_block_pool]["block_count"] + 1
                else:
                    rewards[current_block_epoch]["pools"][current_block_pool]["block_count"] = 1
            else:
                print(f"pool {current_block_pool} received no rewards but created a block in epoch {current_block_epoch}!")
                rewards[current_block_epoch]["pools"][current_block_pool] = { "block_count": 1, "received": 0, "distributed": 0 }


        current_block_hash = current_block["parent"]
        current_block = parse_block(get_block(current_block_hash))


def parse_block(block):
    return {
      "epoch": int(block[16:24], 16),
      "slot": int(block[24:32], 16),
      "parent": block[104:168],
      "pool": block[168:232],
    }

def create_app():
    app = Flask(__name__)

    @app.route('/api/rewards/epoch/<epoch>')
    def rewards_epoch(epoch):
        if epoch in rewards:
            return json.dumps(rewards[epoch])
        else:
            abort(404, description=f"No rewards found for epoch {epoch}")

    @app.route('/api/rewards/total')
    def rewards_total_api():
        return json.dumps(rewards_total)

    @app.route('/api/rewards/account/<pubkey>')
    def rewards_account_api(pubkey):
        if pubkey in rewards_total["accounts"]:
            data = { "total": rewards_total["accounts"][pubkey] }
            data["epochs"] = {}
            for epoch in rewards:
                if pubkey in rewards[epoch]["accounts"]:
                    data["epochs"][epoch] = rewards[epoch]["accounts"][pubkey]
        else:
            abort(404, description=f"No rewards found for account {pubkey}")
        return json.dumps(data)

    @app.route('/api/rewards/pool/<poolid>')
    def rewards_pool_api(poolid):
        if poolid in rewards_total["pools"]:
            data = { "total": rewards_total["pools"][poolid] }
            data["epochs"] = {}
            for epoch in rewards:
                if poolid in rewards[epoch]["pools"]:
                    data["epochs"][epoch] = rewards[epoch]["pools"][poolid]

        else:
            abort(404, description=f"No rewards found for pool {poolid}")
        return json.dumps(data)

    return app

def parseEpochRewards(file_name, epoch, aggregate=False):
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
            pools[ident] = { "received": int(recv), "distributed": int(item["distributed"]), "block_count": 0 }
        elif jtype == "account":
            addr = str(convertHexPubKey(ident))
            accounts[addr] = int(recv)
    if aggregate:
        count_pool_blocks_epoch(epoch)
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
                rewards_total["pools"][pool] = { "received": 0, "distributed": 0, "block_count": 0 }
            rewards_total["pools"][pool]["received"] = rewards_total["pools"][pool]["received"] + pool_data["received"]
            rewards_total["pools"][pool]["distributed"] = rewards_total["pools"][pool]["distributed"] + pool_data["distributed"]
            rewards_total["pools"][pool]["block_count"] = rewards_total["pools"][pool]["block_count"] + pool_data["block_count"]
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
    start_time = time.time()
    filename = event.src_path
    csvfile = os.path.splitext(filename)[0]
    _, _, epoch, _ = filename.split('-')
    # rewards are distributed for the previous epoch
    epoch = str(int(epoch) - 1)
    aggregate=True
    try:
        get_tip()
    except:
        aggregate=False
    rewards[epoch] = parseEpochRewards(csvfile, epoch, aggregate=aggregate)
    end_time = time.time()
    duration = end_time - start_time
    print(f"(watchdog): parsed epoch {epoch} in {duration} seconds")

parse_event_handler.on_created = parseFileEvent
parse_event_handler.on_modified = parseFileEvent

file_observer  = Observer()
file_observer.schedule(parse_event_handler, "./", recursive=False)

file_observer.start()

# parse all reward export csv files in order of time created
start_time = time.time()
files = glob.glob(csvFilePath)
files.sort(key=os.path.getmtime)
for filename in files:
    start_time_epoch = time.time()
    csvfile = os.path.splitext(filename)[0]
    _, _, epoch, _ = filename.split('-')
    # rewards are distributed for the previous epoch
    epoch = str(int(epoch) - 1)
    rewards[epoch] = parseEpochRewards(csvfile, epoch)
    end_time_epoch = time.time()
    duration_epoch = end_time_epoch - start_time_epoch
    print(f"(initial startup): parsed epoch {epoch} in {duration_epoch} seconds")
try:
    pass
    count_pool_blocks_all()
except:
    print("API not available to count blocks!")
update_totals()
end_time = time.time()
duration = end_time - start_time
print(f"(initial startup): initialized in {duration} seconds")

# start the rest api
app = create_app()
