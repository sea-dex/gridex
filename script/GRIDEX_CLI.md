# gridex-cli.sh

`script/gridex-cli.sh` is a helper script for interacting with the deployed GridEx router.

It supports:

- admin operations on the router and vault
- view/read-only queries
- user actions such as canceling grids and withdrawing profits
- timelock-aware admin flows after ownership is transferred to `TimelockController`

## Prerequisites

Set these environment variables in `.env` or export them in your shell:

RPC: 

BSC Testnet:  https://bsc-testnet-rpc.publicnode.com
BSC Mainnet:  https://bsc-dataseed1.binance.org
Base Mainnet: 
ETH Mainnet:  https://eth-mainnet.alchemyapi.io/v2/pwc5rmJhrdoaSEfimoKEmsvOjKSmPDrP


```bash
export RPC_URL="https://..."
export PRIVATE_KEY="0x..."
export ROUTER_ADDRESS="0x..."
```

Optional timelock variables:

```bash
export TIMELOCK_ADDRESS="0x..."
export TIMELOCK_ACTION="schedule"   # or execute
export TIMELOCK_DELAY="600"          # optional override
export TIMELOCK_PREDECESSOR="0x0000000000000000000000000000000000000000000000000000000000000000"
export TIMELOCK_SALT="0x0000000000000000000000000000000000000000000000000000000000000000"
```

Notes:

- `TIMELOCK_ADDRESS` is optional. If omitted, the script uses `owner()` on the router.
- `TIMELOCK_SALT` must be the same for both `schedule` and `execute`.
- `admin_pause` can still be sent directly by the configured guardian.

## Basic Usage

Show help:

```bash
./script/gridex-cli.sh help
```

Read router state:

```bash
./script/gridex-cli.sh view_get_oneshot_fee
./script/gridex-cli.sh view_is_strategy_whitelisted 0xStrategy
./script/gridex-cli.sh view_get_grid_order 123
```

User actions:

```bash
./script/gridex-cli.sh cancel_grid 0xRecipient 456 0
./script/gridex-cli.sh withdraw_profit 456 0xRecipient 0
```

## Admin Calls Before Timelock

If your `PRIVATE_KEY` is the current owner of the target contract, admin calls are sent directly.

Examples:

```bash
./script/gridex-cli.sh admin_set_weth 0xWeth
./script/gridex-cli.sh admin_set_quote_token 0xUsd 100
./script/gridex-cli.sh admin_set_strategy_whitelist 0xStrategy true
./script/gridex-cli.sh admin_set_oneshot_fee 30
./script/gridex-cli.sh admin_unpause
```

## Admin Calls After Timelock

If the router or vault owner is a timelock, the script automatically uses the timelock flow instead of sending directly to the target contract.

### 1. Schedule

```bash
TIMELOCK_ACTION=schedule \
TIMELOCK_SALT=0x1111111111111111111111111111111111111111111111111111111111111111 \
./script/gridex-cli.sh admin_set_quote_token 0xUsd 100
```

### 2. Execute

After the timelock delay has passed, run the exact same command with `TIMELOCK_ACTION=execute` and the same `TIMELOCK_SALT`:

```bash
TIMELOCK_ACTION=execute \
TIMELOCK_SALT=0x1111111111111111111111111111111111111111111111111111111111111111 \
./script/gridex-cli.sh admin_set_quote_token 0xUsd 100
```

This pattern also applies to:

- `admin_set_weth`
- `admin_set_strategy_whitelist`
- `admin_set_oneshot_fee`
- `admin_unpause`
- `admin_rescue_eth`
- `admin_transfer_ownership`
- `admin_set_facet`
- `admin_batch_set_facets`

## Ownership Transfer

Transfer both router and vault ownership:

```bash
./script/gridex-cli.sh admin_transfer_ownership 0xNewOwner
```

Transfer only one side:

```bash
./script/gridex-cli.sh admin_transfer_ownership 0xNewOwner router
./script/gridex-cli.sh admin_transfer_ownership 0xNewOwner vault
```

If ownership has already been moved to timelock, the command will schedule or execute through timelock.

## Emergency Pause

Pause:

```bash
./script/gridex-cli.sh admin_pause
```

Unpause:

```bash
./script/gridex-cli.sh admin_unpause
```

Behavior:

- guardian can call `admin_pause` directly
- owner can call `admin_pause` directly
- `admin_unpause` requires owner authority, so it goes through timelock when the owner is timelock

## Troubleshooting

- `RPC_URL not set`: export `RPC_URL` or add it to `.env`
- `ROUTER_ADDRESS not set`: export `ROUTER_ADDRESS` or add it to `.env`
- `PRIVATE_KEY not set`: required for write operations
- `Resolved owner ... does not look like a TimelockController`: set `TIMELOCK_ADDRESS` explicitly or use the real direct owner key
- timelock execute fails: check that `TIMELOCK_SALT`, target function arguments, and predecessor match the original scheduled operation
