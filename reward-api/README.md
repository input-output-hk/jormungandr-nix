# Reward API

A little API to provide information for each epoch, account, and pool regarding
their rewards blocks, and other accumulated data.

# Usage

1. Using `nix-shell`

```bash
nix-shell --arg customConfig '{ rewardsLog = true; }'
```

2. Using `nixos` module

```nix
services.jormungandr-reward-api.enable = true;
```

# API endpoints

The reward API endpoints give the rewards earned from an epoch, not the epoch the rewards were distributed.

For example, if stake is delegated in epoch 2, in epoch 4 the stake delegation from epoch 2 will be used, and the
rewards correspond to the amount delegated in epoch 4, not epoch 5 when the rewards were distributed.

## `/api/rewards/epoch/<epoch>`

Fetches all rewards data for a specific epoch

## `/api/rewards/account/<pubkey>`

Fetches all rewards details for a specific account public key

## `/api/rewards/pool/<poolid>`

Fetches all rewards details for a specific pool

## `/api/rewards/total`

Fetches aggregated rewards for blockchain since genesis

## `/api/rewards/warmup`

Used for warming up the cache after a fresh deploy, this will much faster overall than a cold start.

# Development

Relevant environment variables:

    JORMUNGANDR_RESTAPI_URL
    JORMUNGANDR_GRAPHQL_URL
    JORMUNGANDR_REWARD_DUMP_DIRECTORY

For development, you can use [watchexec](https://github.com/watchexec/watchexec):

    watchexec -r -- crystal ./src/reward-api.cr
