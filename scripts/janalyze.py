#!/usr/bin/env nix-shell
#!nix-shell -p python3Packages.requests python3Packages.tabulate -i python3

"""
Jormungandr Analysis Tools
"""

__version__ = "0.1.0"

import argparse, requests, os, json, sys
from argparse import RawTextHelpFormatter
from requests.exceptions import HTTPError
from tabulate import tabulate


globalAggregate = None
globalEpochBlocks = None
globalPools = None

api_url_base = None
api_url = None


def get_api(path):
    r = endpoint(f'{api_url}/{path}')
    return r.text


def get_tip():
    return get_api("tip")


def get_block(block_id):
    r = endpoint(f'{api_url}/block/{block_id}')
    hex_block = r.content.hex()
    return hex_block


def parse_block(block):
    return {
      "epoch": int(block[16:24], 16),
      "slot": int(block[24:32], 16),
      "parent": block[104:168],
      "pool": block[168:232],
    }

def aggregateall():
    tip = get_tip()
    block = parse_block(get_block(tip))
    currentEpoch = block['epoch']
    poolTotal = {}
    blockTotal = 0

    while block["parent"] != ("0" * 64):
        if args.aggregateall > 0:
            if (currentEpoch - args.aggregateall + 1) > block['epoch']:
                break
        pool = block["pool"]
        if pool not in poolTotal:
            poolTotal[pool] = {}
            poolTotal[pool]['blocks'] = 1
        else:
            poolTotal[pool]['blocks'] = poolTotal[pool]['blocks'] + 1
        block = parse_block(get_block(block['parent']))
        blockTotal += 1
        lowestEpoch = block['epoch']

    if args.aggregateall > 0:
        print(f'\nJormungandr Block Aggregate for epochs {lowestEpoch + 1} - {currentEpoch}:\n')
    else:
        print('\nJormungandr Overall Block Aggregate:\n')

    headers = [f'Pool (Node ID)', "Blocks (#)", "Block Percent (%)"]
    table = []
    for pool, data in poolTotal.items():
       record = [ pool, data['blocks'], data['blocks'] / blockTotal * 100 ]
       table.append(record)
    print(f'{tabulate(sorted(table, key=lambda x: x[0]), headers, tablefmt="psql")}')
    print(f'TotalBlocks: {blockTotal} \n')

def aggregate(silent=False):

    global globalAggregate
    global globalEpochBlocks
    tip = get_tip()
    block = parse_block(get_block(tip))
    epochBlockTotal = {}
    currentEpoch = block['epoch']
    epochs = {}
    pools = {}

    while block["parent"] != ("0" * 64):
        if args.full == False:
            if (currentEpoch - args.aggregate + 1) > block['epoch']:
                break
        epoch = block['epoch']
        parent = block['parent']
        pool = block['pool']
        if epoch not in epochs:
            epochs[epoch] = {}
            epochBlockTotal[epoch] = 0

        if pool not in epochs[epoch]:
            epochs[epoch][pool] = {}
            epochs[epoch][pool]['blocks'] = 1
            epochBlockTotal[epoch] = epochBlockTotal[epoch] + 1
        else:
            epochs[epoch][pool]['blocks'] = epochs[epoch][pool]['blocks'] + 1
            epochBlockTotal[epoch] = epochBlockTotal[epoch] + 1
        block = parse_block(get_block(block['parent']))

    for epoch, epochData in epochs.items():
        epochs[epoch]['stats'] = {}
        epochs[epoch]['stats']['blocksum'] = epochBlockTotal[epoch]
        for pool, poolData in epochData.items():
            if pool != 'stats':
                epochs[epoch][pool]['percent'] = poolData['blocks'] / epochBlockTotal[epoch] * 100

    if silent == False:
        if args.json == True:
            print(json.dumps(epochs, sort_keys=True))
        else:
            print('\nJormungandr Epoch Block Aggregate:\n')
            for epoch, epochData in epochs.items():
                headers = [f'EPOCH {epoch}, Pool (Node ID)', "Blocks (#)", "Block Percent (%)"]
                table = []
                for pool, data in epochData.items():
                    if pool != 'stats':
                        record = [ pool, data['blocks'], data['percent'] ]
                        table.append(record)
                if args.bigvaluesort == True:
                    print(f'{tabulate(sorted(table, key=lambda x: x[1], reverse=True), headers, tablefmt="psql")}')
                else:
                    print(f'{tabulate(sorted(table, key=lambda x: x[0]), headers, tablefmt="psql")}')
                print(f'{"Totalblocks:":<21}{epochData["stats"]["blocksum"]}\n\n')
    globalAggregate = epochs


def distribution(silent=False):
    global globalPools
    epoch = 0
    unassigned = 0
    dangling = 0
    stakeSum = 0
    totalPercentStaked = 0
    total = 0
    pools = {}

    r = endpoint(f'{api_url}/stake')
    raw = r.json()

    epoch = raw['epoch']
    dangling = raw['stake']['dangling']
    unassigned = raw['stake']['unassigned']

    if args.bigvaluesort == True:
        sortedRaw = sorted(raw['stake']['pools'], key = lambda x: x[1], reverse=True)
    else:
        sortedRaw = sorted(raw['stake']['pools'])
    for [pool, stake] in sortedRaw:
        pools[pool] = {}
        pools[pool]['stake'] = stake
        pools[pool]['percent'] = 0
        stakeSum = stakeSum + stake

    total = stakeSum + unassigned + dangling
    totalPercentStaked = stakeSum / total

    # Calculate percentage stake delegation of total staked ADA
    for pool in pools.keys():
        pools[pool]['percent'] = pools[pool]['stake'] / stakeSum * 100

    pools['stats'] = {}
    pools['stats']['epoch'] = epoch
    pools['stats']['dangling'] = dangling
    pools['stats']['unassigned'] = unassigned
    pools['stats']['total'] = total
    pools['stats']['stakesum'] = stakeSum
    pools['stats']['totalpercentstaked'] = totalPercentStaked

    if silent == False:
        if args.json == True:
            print(json.dumps(pools, sort_keys=True))
        else:
            print('\nJormungandr Stake Pool Distribution:\n')
            print(f'{"Epoch:":<21}{epoch}')
            print(f'{"Dangling:":<21}{dangling / 1e6:,.6f} ADA')
            print(f'{"Unassigned:":<21}{unassigned / 1e6:,.6f} ADA')
            print(f'{"Total:":<21}{total / 1e6:,.6f} ADA')
            print(f'{"TotalStaked:":<21}{stakeSum / 1e6:,.6f} ADA')
            print(f'{"TotalPercentStaked:":<21}{totalPercentStaked * 100:.2f}%\n')
            headers = [f'EPOCH {epoch}, Pool (Node ID)', "Stake (ADA)", "Percent (%)"]
            table = []
            otherRecord=[0,0,0]
            for pool, poolData in pools.items():
                if pool != 'stats':
                    if args.nozero == False or poolData['stake'] != 0:
                        if args.dust is not None and (poolData['stake'] < args.dust * 1e6 ):
                            otherRecord = [x + y for x, y in zip(otherRecord, [1,float(poolData['stake'] / 1e6),float(0 if poolData['percent'] is None else poolData['percent'])])]
                        else:
                            record = [ pool, poolData['stake'] / 1e6, poolData['percent'] ]
                            table.append(record)
            if otherRecord[0]>0:
                otherRecord[0]="Other " + str(otherRecord[0]) + " pools with < " + str(args.dust) + " ADA in each"
                table.append(otherRecord)
            if args.bigvaluesort == True:
                print(f'{tabulate(sorted(table, key=lambda x: x[1], reverse=True), headers, tablefmt="psql", floatfmt=("%s", "0.6f"))}\n\n')
            else:
                print(f'{tabulate(sorted(table, key=lambda x: x[0]), headers, tablefmt="psql", floatfmt=("%s", "0.6f"))}\n\n')
    globalPools = pools


def crossref():

    if globalAggregate == None:
        args.aggregate = 1
        aggregate(silent=True)

    if globalPools == None:
        distribution(silent=True)

    crossref = globalPools
    epoch = crossref['stats']['epoch']
    for pool, poolData in crossref.items():
        if pool != 'stats':
            if pool in globalAggregate[epoch]:
                crossref[pool]['blocks'] = globalAggregate[epoch][pool]['blocks']
                crossref[pool]['percentBlocks'] = globalAggregate[epoch][pool]['percent']
            else:
                crossref[pool]['blocks'] = None
                crossref[pool]['percentBlocks'] = None

    if args.json == True:
        print(json.dumps(crossref, sort_keys=True))
    else:
        print('\nJormungandr Stake and Block Distribution Cross Reference:\n')
        print(f'{"Epoch:":<21}{epoch}')
        print(f'{"Dangling:":<21}{crossref["stats"]["dangling"] / 1e6:,.6f} ADA')
        print(f'{"Unassigned:":<21}{crossref["stats"]["unassigned"] / 1e6:,.6f} ADA')
        print(f'{"TotalADA:":<21}{crossref["stats"]["total"] / 1e6:,.6f} ADA')
        print(f'{"TotalBlocks:":<21}{globalAggregate[epoch]["stats"]["blocksum"]}')
        print(f'{"TotalStaked:":<21}{crossref["stats"]["stakesum"] / 1e6:,.6f} ADA')
        print(f'{"TotalPercentStaked:":<21}{crossref["stats"]["totalpercentstaked"] * 100:.2f}%\n')
        headers = [f'EPOCH {epoch}, Pool (Node ID)', "Stake (ADA)", "Blocks (#)", "PercentStaked (%)", "PercentBlocks (%)"]
        table = []
        otherRecord=[0,0,0,0,0]
        for pool, poolData in crossref.items():
            if pool != 'stats':
                if args.nozero == False or (not (poolData['stake'] == 0 and poolData['blocks'] == None)):
                    if args.dust is not None and (poolData['stake'] < args.dust * 1e6 ):
                        otherRecord = [x + y for x, y in zip(otherRecord, [1,float(poolData['stake'] / 1e6),int(0 if poolData['blocks'] is None else poolData['blocks']),float(0 if poolData['percent'] is None else poolData['percent']), float(0 if poolData['percentBlocks'] is None else poolData['percentBlocks'])])]
                    else:
                        record = [ pool, poolData['stake'] / 1e6, poolData['blocks'], poolData['percent'], poolData['percentBlocks'] ]
                        table.append(record)
        if otherRecord[0]>0:
            otherRecord[0]="Other " + str(otherRecord[0]) + " pools with < " + str(args.dust) + " ADA in each"
            table.append(otherRecord)
        if args.bigvaluesort == True:
            print(f'{tabulate(sorted(table, key=lambda x: x[1], reverse=True), headers, tablefmt="psql", floatfmt=("%s", "0.6f", "g", "g", "g"))}\n\n')
        else:
            print(f'{tabulate(sorted(table, key=lambda x: x[0]), headers, tablefmt="psql", floatfmt=("%s", "0.6f", "g", "g", "g"))}\n\n')


def stats():
    r = endpoint(f'{api_url}/node/stats')
    if args.json == True:
        print(json.dumps(r.json(), sort_keys=True))
    else:
        print('Current node stats:\n')
        print(json.dumps(r.json(), sort_keys=True, indent=2))


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


def check_int(value):
    ivalue = int(value)
    if ivalue <= 0:
        raise argparse.ArgumentTypeError("%s is an invalid positive int value" % value)
    return ivalue


def main():
    global api_url_base
    global api_url

    if args.restapi is not None:
        api_url_base = args.restapi
    else:
        api_url_base = os.environ.get("JORMUNGANDR_RESTAPI_URL", "http://localhost:3001/api")
    api_url = f"{api_url_base}/v0"

    if args.stats == True:
        stats()

    if args.aggregateall is not None:
        aggregateall()

    if args.aggregate is not None:
        aggregate()

    if args.distribution == True:
        distribution()

    if args.crossref == True:
        crossref()

    exit(0)


if __name__ == "__main__":
    if len(sys.argv) == 1:
        print(f'\nRun `{sys.argv[0]} -h` for helpi and usage information\n')
        exit(0)

    parser = argparse.ArgumentParser(description=(
        "Jormungandr analysis tools\n\n"),
        formatter_class=RawTextHelpFormatter)

    parser.add_argument("-aa", "--aggregateall", nargs="?", metavar="X", type=check_int, const=0,
                        help="Calculate total block creation per pool for X epochs time starting with the tip or leave blank for all")

    parser.add_argument("-a", "--aggregate", nargs="?", metavar="X", type=check_int, const=1,
                        help="Calculate aggregate block creation per pool for X epochs starting with the tip epoch (default = 1)")

    parser.add_argument("-b", "--bigvaluesort", action="store_true",
                        help="Show non <-j|--json> output sorted by big to small value rather than keys where possible")

    parser.add_argument("-d", "--distribution", action="store_true",
                        help="Calculate the stake distribution for the current epoch only")

    parser.add_argument("-u", "--dust", nargs="?", metavar="X", type=check_int, const=1,
                        help="Combine dust pools with less than X ADA stake (default = 1 ADA)")

    parser.add_argument("-f", "--full", action="store_true",
                        help="Calculate the full epoch history where possible")

    parser.add_argument("-j", "--json", action="store_true",
                        help="Output raw json only")

    parser.add_argument("-n", "--nozero", action="store_true",
                        help="Don't show zero value staking pools (blocks minted or stake valued)")

    parser.add_argument("-s", "--stats", action="store_true",
                        help="Show the current node stats")

    parser.add_argument("-v", "--version", action="store_true",
                        help="Show the program version and exit")

    parser.add_argument("-x", "--crossref", action="store_true",
                        help="Analyse the current epoch, cross referencing both block aggregate and stake distributions")

    parser.add_argument("-r", "--restapi", nargs="?", metavar="RESTAPI", type=str, const="http://127.0.0.1:3001/api",
                        help="Set the rest api to utilize; by default: \"http://127.0.0.1:3001/api\".  An env var of JORMUNGANDR_RESTAPI_URL can also be seperately set. ")

    args = parser.parse_args()

    if args.version:
        print(f'Version: {__version__}\n')
        exit(0)
    main()