# GridSol (Pinocchio)

This directory contains a Solana grid-trading program implemented with Pinocchio (not Anchor).

## Scope (rebalance excluded)

Implemented protocol-level behaviors:
- Admin config initialization
- Pause/unpause
- Update protocol fee / oneshot protocol fee
- Create grid
- Fill ask/bid order
- Cancel grid
- Withdraw grid profits (accounting state)
- Withdraw protocol fees

## Program architecture

- `programs/gridsol/src/lib.rs`: Pinocchio entrypoint
- `programs/gridsol/src/processor.rs`: Instruction dispatch + handlers
- `programs/gridsol/src/instruction.rs`: Borsh instruction schema
- `programs/gridsol/src/state.rs`: Config/Grid state + fee split
- `programs/gridsol/src/error.rs`: Custom error codes

## Account model (minimal)

Each instruction expects the following account order:

1. `InitializeConfig`
- `[signer] admin`
- `[writable] config` (program-owned account)

2. `SetPause`, `SetProtocolFee`, `SetOneshotProtocolFee`
- `[signer] admin`
- `[writable] config`

3. `CreateGrid`
- `[signer] owner`
- `[writable] config`
- `[writable] grid`
- `[readonly] token_program`
- `[writable] owner_base_ata`
- `[writable] owner_quote_ata`
- `[writable] base_vault`
- `[writable] quote_vault`
- `[readonly] grid_signer` (PDA address)
- `token_program` supports both:
  - SPL Token (`Tokenkeg...`)
  - SPL Token-2022 (`TokenzQd...`)

4. `FillOrder`
- `[signer] taker`
- `[readonly] config`
- `[writable] grid`
- `[readonly] token_program`
- `[writable] taker_base_ata`
- `[writable] taker_quote_ata`
- `[writable] base_vault`
- `[writable] quote_vault`
- `[readonly] grid_signer`
- params:
  - `side`: taker side (`0 = fillAsk`, `1 = fillBid`)
  - `order_side`: target order side (`0 = ask order`, `1 = bid order`)
  - `order_index`, `base_amount`
- supports forward and reversed fills (except reversed oneshot orders)

5. `FillOrders` (batch fill, cross-grid)
- `[signer] taker`
- `[readonly] config`
- `[readonly] token_program`
- `[writable] taker_base_ata`
- `[writable] taker_quote_ata`
- for each fill target append 4 accounts:
  - `[writable] grid`
  - `[writable] base_vault`
  - `[writable] quote_vault`
  - `[readonly] grid_signer`
- params:
  - `fills: Vec<FillTarget>`
  - each `FillTarget` = `{ side, order_side, order_index, base_amount }`
- supports cross-grid batching (one tx can fill multiple grids/orders)

6. `CancelOrder`
- `[signer] owner`
- `[writable] grid`
- `[readonly] token_program`
- `[writable] base_vault`
- `[writable] quote_vault`
- `[writable] owner_base_ata`
- `[writable] owner_quote_ata`
- `[readonly] grid_signer`

7. `CancelGrid`
- `[signer] owner`
- `[writable] grid`
- `[readonly] token_program`
- `[writable] base_vault`
- `[writable] quote_vault`
- `[writable] owner_base_ata`
- `[writable] owner_quote_ata`
- `[readonly] grid_signer`

8. `WithdrawProfits`
- `[signer] owner`
- `[writable] grid`
- `[readonly] token_program`
- `[writable] quote_vault`
- `[writable] owner_quote_ata`
- `[readonly] grid_signer`

9. `WithdrawProtocolFees`
- `[signer] admin`
- `[readonly] config`
- `[writable] grid`
- `[readonly] token_program`
- `[writable] quote_vault`
- `[writable] admin_quote_ata`
- `[readonly] grid_signer`

## PDA signer convention

The current implementation signs vault outgoing CPI transfers with seeds:

- `b\"grid_signer\"`
- `owner_pubkey_bytes`
- `grid_id_le_bytes`
- `signer_bump` (passed in `CreateGridParams` and stored on grid)

Clients must derive and pass a matching `grid_signer` + `signer_bump`.

## Important note on settlement

Current version implements state machine accounting and SPL token CPI settlement for:
- create-time deposits
- fill-time taker/vault transfers
- withdraw profits transfers
- withdraw protocol fees transfers
