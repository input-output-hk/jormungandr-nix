#!/usr/bin/env python

from prometheus_client import Gauge
from prometheus_client import Summary
from prometheus_client import start_http_server
from dateutil.parser import parse
import time, sys, warnings, os, traceback, subprocess, json

EXPORTER_PORT = int(os.getenv('PORT', '8000'), 10)
SLEEP_TIME = int(os.getenv('SLEEP_TIME', '10'), 10)
JORMUNGANDR_API = os.getenv('JORMUNGANDR_RESTAPI_URL',
                  os.getenv('JORMUNGANDR_API', 'http://127.0.0.1:3101/api'))
os.environ['JORMUNGANDR_RESTAPI_URL'] = JORMUNGANDR_API
ADDRESSES = os.getenv('MONITOR_ADDRESSES', '').split()
NODE_METRICS = [
    "blockRecvCnt",
    "lastBlockDate",
    "lastBlockFees",
    "lastBlockHash",
    "lastBlockHeight",
    "lastBlockSum",
    "lastBlockTime",
    "lastBlockTx",
    "txRecvCnt",
    "uptime",
    "connections",
    "lastBlockEpoch",
    "lastBlockSlot"
]
PIECE_METRICS = [
    "lastBlockHashPiece1",
    "lastBlockHashPiece2",
    "lastBlockHashPiece3",
    "lastBlockHashPiece4",
    "lastBlockHashPiece5",
    "lastBlockHashPiece6",
    "lastBlockHashPiece7",
    "lastBlockHashPiece8"
]
NaN = float('NaN')


def metric_gauge(metric):
    return Gauge(f'jormungandr_{metric}', 'Jormungandr {metric}')


def piece_gauge(metric):
    return Gauge(f'jormungandr_{metric}', 'Jormungandr {metric}')


jormungandr_metrics = {metric: metric_gauge(metric) for metric in NODE_METRICS}
jormungandr_pieces = {metric: piece_gauge(metric) for metric in PIECE_METRICS}

jormungandr_funds = Gauge(f'jormungandr_address_funds',
                                 f'Jomungandr Address funds in Lovelace',
                                 ['addr'])
jormungandr_counts = Gauge(f'jormungandr_address_counts',
                                 f'Jomungandr Address counter',
                                 ['addr'])

to_reset = [
    jormungandr_metrics,
    jormungandr_pieces
]

to_reset_with_labels = [
    jormungandr_funds,
    jormungandr_counts
]


JORMUNGANDR_METRICS_REQUEST_TIME = Summary(
    'jormungandr_metrics_process_time',
    'Time spent processing jormungandr metrics')


# Decorate function with metric.
@JORMUNGANDR_METRICS_REQUEST_TIME.time()
def process_jormungandr_metrics():
    # Process jcli returned metrics
    metrics = jcli_rest(['node', 'stats', 'get'])

    lsof = subprocess.Popen(
            ['@lsof@', '-nPi', ':3000', '-sTCP:ESTABLISHED'],
            stdout=subprocess.PIPE)
    wc = subprocess.check_output(['@wc@', '-l'], stdin=lsof.stdout)
    lsof.wait()
    metrics['connections'] = int(wc, 10)


    try:
        metrics['lastBlockTime'] = parse(metrics['lastBlockTime']).timestamp()
    except:
        print(f'failed to parse lastBlockTime: {metrics["lastBlockTime"]}')
        metrics['lastBlockTime'] = NaN

    try:
        metrics['lastBlockEpoch'] = metrics['lastBlockDate'].split('.')[0]
        metrics['lastBlockSlot'] = metrics['lastBlockDate'].split('.')[1]
    except:
        print(f'failed to parse lastBlockDate into pieces: {metrics["lastBlockDate"]}')

    for metric, gauge in jormungandr_metrics.items():
        gauge.set(sanitize(metrics[metric]))

    # Process pieced metrics from jcli parent metrics
    try:
        blockHashPieces = {}
        lastBlockHashProcess = hex(int(metrics['lastBlockHash'],16))[2:]
        for i, (x, y) in enumerate(list(zip(range(-64,8,8),range(-56,8,8))),1):
            if y == 0:
                y = None
            blockHashPieces['lastBlockHashPiece'+str(i)] = int(lastBlockHashProcess[slice(x,y)],16)
        for metric, gauge in jormungandr_pieces.items():
            gauge.set(sanitize(blockHashPieces[metric]))
    except:
        print(f'failed to parse lastBlockHash pieces: {metrics["lastBlockHash"]}')
        for gauge in jormungandr_pieces.values():
            gauge.set(NaN)


JORMUNGANDR_ADDRESSES_REQUEST_TIME = Summary(
    'jormungandr_addresses_process_time',
    'Time spent processing jormungandr addresses')


@JORMUNGANDR_ADDRESSES_REQUEST_TIME.time()
def process_jormungandr_addresses():
    for address in ADDRESSES:
        data = jcli_rest(['account', 'get', address])
        jormungandr_funds.labels(addr=address).set(sanitize(data['value']))
        jormungandr_counts.labels(addr=address).set(sanitize(data['counter']))


def sanitize(metric):
    if isinstance(metric, str):
        try:
            metric = float(metric)
        except ValueError:
            try:
                metric = int(metric, 16)
            except ValueError:
                metric = NaN
    elif not isinstance(metric, (float, int)):
        metric = NaN
    return metric


def jcli_rest(args):
    flags = ['--host', JORMUNGANDR_API, '--output-format', 'json']
    params = ['@jcli@', 'rest', 'v0'] + args + flags
    result = subprocess.run(params, stdout=subprocess.PIPE)
    return json.loads(result.stdout)


if __name__ == '__main__':
    # Start up the server to expose the metrics.
    print(f"Starting metrics at http://localhost:{EXPORTER_PORT}")
    start_http_server(EXPORTER_PORT)
    # Main Loop: Process all API's and sleep for a certain amount of time
    while True:
        try:
            process_jormungandr_metrics()
            process_jormungandr_addresses()
        except:
            traceback.print_exc(file=sys.stdout)
            print("failed to process jormungandr metrics")
            for d in to_reset:
                for gauge in d.values():
                    gauge.set(NaN)
            for gauge in to_reset_with_labels:
                gauge._metrics.clear()
        time.sleep(SLEEP_TIME)
