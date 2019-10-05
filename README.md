# Setting up nix

Setting up the IOHK binary cache will significantly decrease build time.
Add the below to the nix.conf file in /etc/nix/nix.conf   (create it if it does not exist):

```
substituters = https://cache.nixos.org https://hydra.iohk.io
trusted-substituters =
trusted-public-keys = hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

If you are runnning Windows 10 with WSL and Ubuntu, you will also need to add the following flags to fix two NixOS required workarounds needed for NixOS to run on WSL:
- Work around missing cgroups support https://github.com/Microsoft/WSL/issues/994
- Work around incorrect file locking https://github.com/Microsoft/WSL/issues/2395

```
sandbox = false
use-sqlite-wal = false
```

On NixOS this can be done with:

```
    nix.binaryCaches = [
      "https://cache.nixos.org"
      "https://hydra.iohk.io"
    ];
    nix.binaryCachePublicKeys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
    ];
```

# A docker image

```
docker load < $(nix-build -A docker-images.jormungandr-standalone --no-link)
docker run -t -e GELF='true' jormungandr-standalone:0.3.0
```
(remove `-e GELF='true'` if you don't want to send jormungandr's logs to iohk)

# A nix-shell for Jormungandr

To drop into a shell ready to connect to the testnet, clone this repo and run:
```
nix-shell
```

After you've generated secrets in `state-jormungandr` using
`create-stake-pool` run the node with `nix-shell --arg customConfig '{ staking = true; }'` to launch the node as a stake pool with your `secret.yaml`.

__Important__ if you want to help IOHK diagnoctic issues you may encouter

Set logger output to `gelf` with
```
--arg customConfig '{ sendLogs = true; }'
```

Note that any number of options can be combined in `customConfig`. For example to send logs and run as a stake pool use:
```
--arg customConfig '{ sendLogs = true; staking = true; }'
```

that way jormungandr logs will be sent to iohk testnet log server and will be invaluable inputs to diagnoctic issues.

One other useful feature, if you run jormungandr on a separate
host and can access the REST API from the host your running the
nix-shell, use:

```
--arg customConfig '{restListen = "192.168.1.1:3101"'
```

to connect to the API at host 192.168.1.1 on port 3101.


Once in the shell run `run-jormungandr` to start jormungandr.


# Nix-shell for self node and creating new genesis files

The self node generation scripts have been moved to `nix-shell -A bootstrap`.

Unless you're developing a feature in isolation from the network, like a custom explorer or wallet, you have no need for these instructions and should refer above to the networked testnet nix-shell.

To regenerate the config (in case of incompatible change in jormungandr after updating the commit), run `generate-config`

You can tweak the blockchain configuration through nix-shell parameters, eg.:
```
nix-shell -A bootstrap --arg customConfig '{ faucetAmounts = [ 100000 1234444 34556 ]; numberOfStakePools = 2; logger_output = gelf; }'
```

This will put the new bootstrap config in state-jormungandr-bootstrap.


TODO: update below params to be up to date.

## Available parameters

| Parameter  | Default value | Description
| ------------- | ------------- | ------------- |
| `--argstr package` | `jormungandrMaster` | Jormungandr package to use. Use `jormungandr` for last stable release. `jormungandrMaster` for last master branch build. |
| `--argstr rootDir` | `/tmp` | Parent directory of the working directory (generated). |
| `--argstr block0_consensus` | `genesis_praos`  | Consensus algorithm initialy used. `bft` or `genesis_praos` |
| `--arg faucetAmounts`  | `[ 1000000000 ]` | List of amounts (space separated) in Lovelace that will be attributed to faucet addresses in block 0. |
| `--arg numberOfStakePools` | `0` if `bft`, `1` if `genesis` | Number of stake pools initialy registered. Each faucet will own on of the stake pool (hence `numberOfStakePools` must be ≤ `faucetAmounts` length). |
| `--arg numberOfLeaders` | `1` | Number of BFT leaders (keys will be generated). |
| `--arg block0_date` | `1550822014` (February 22, 2019) | the official start time of the blockchain, in seconds since UNIX EPOCH |
| `--arg isProduction` | `false` | if `true` (meant for production) use `production` for discrimination otherwise use `test`. |
| `--arg slots_per_epoch` | `60` | Number of slots in each epoch |
| `--arg slot_duration` | `10` | The slot duration, in seconds, is the time between the creation of 2 blocks |
| `--arg epoch_stability_depth` | `10` | The number of blocks (*10) per epoch |
| `--arg bft_slots_ratio` | `0` | Genesis praos parameter D |
| `--arg consensus_genesis_praos_active_slot_coeff` | `0.1` | Genesis praos active slot coefficient. Determines minimum stake required to try becoming slot leader, must be in range (0,1] |
| `--arg max_number_of_transactions_per_block` | `255` | This is the max number of messages allowed in a given Block |
| `--arg linear_fees_constant` | `10` | parameter in fee calculation [1] |
| `--arg linear_fees_coefficient` | `0` | parameter in fee calculation [1] |
| `--arg linear_fees_certificate` | `0` | parameter in fee calculation [1] |
| `--arg kes_update_speed` | `43200` (12 hours) | The speed to update the KES Key in seconds |
| `--argstr storage` | `./storage` | path to the storage. |
| `--argstr rest_listen` | `127.0.0.1:8443` | listen address of the rest endpoint |
| `--arg logger_level` | `info` | logger level:  "off", "critical", "error", "warn", "info", "debug", "trace".
| `--argstr logger_format` | `plain` | log output format - `plain` or `json`. |
| `--argstr logger_output` | `stderr` | log output - `stderr`, `gelf` (graylog), `syslog` (unix only) or `journald` |
| `--argstr logger_backend` | `monitoring.stakepool.cardano-testnet.iohkdev.io:12201` if `gelf` | Graylog server to ouput the log to, default to iohk cardano-testnet graylog server (for debug purposes). |
| `--argstr logs_id` | generated uuid | Uniquely identify the logs of this node on the Graylog server. Please comunicate this id when filling issues. |
| `--argstr public_address` | `/ip4/127.0.0.1/tcp/8299` |  the address to listen from and accept connection from. This is the public address that will be distributed to other peers of the network that may find interest into participating to the blockchain dissemination with the node. |
| `--argstr  trusted_peers` | none | comma seperated list of of nodes to connect to in order to bootstrap the p2p topology (and bootstrap our local blockchain). Eg. `/ip4/104.24.28.11/tcp/8299,/ip4/104.24.29.11/tcp/8299` |
| `--argstr topics_of_interest` | `messages=high,blocks=high` if pools are registered, `messages=low,blocks=normal` otherwise | the different topics (comma separated) we are interested to hear about: - messages: notify other peers this node is interested about Transactions, typical setting for a non mining node: "low", for a stakepool: "high"; - blocks: notify other peers this node is interested about new Blocs, typical settings for a non mining node: "normal", for a stakepool: "high"; |

[1]: fee(num_bytes, has_certificate) = constant + num_bytes * coefficient + has_certificate * certificate
