# GridEx Protocol Security Audit Report

**Audit Date:** 2026-02-12  
**Version:** Current codebase  
**Auditor:** Security Review  
**Solidity Version:** ^0.8.33

---

## Executive Summary

This security audit covers the GridEx decentralized grid trading protocol. The protocol implements a grid trading system with support for ETH and ERC20 tokens, featuring order placement, filling, cancellation, and profit withdrawal.

### Overall Risk Assessment: **MEDIUM**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 5 |
| Low | 8 |
| Informational | 6 |

---

## Table of Contents

1. [Critical Findings](#1-critical-findings)
2. [High Severity Findings](#2-high-severity-findings)
3. [Medium Severity Findings](#3-medium-severity-findings)
4. [Low Severity Findings](#4-low-severity-findings)
5. [Informational Findings](#5-informational-findings)
6. [Centralization Risks](#6-centralization-risks)
7. [Gas Optimization](#7-gas-optimization)
8. [Conclusion](#8-conclusion)

---

## 1. Critical Findings

**No critical vulnerabilities found.**

---

## 2. High Severity Findings

### H-01: Reentrancy Vulnerability in Callback Pattern

**Location:** [`GridEx.sol`](src/GridEx.sol:253-259), [`GridEx.sol`](src/GridEx.sol:367-378)

**Description:** The `fillAskOrder` and `fillBidOrder` functions use a callback pattern that transfers tokens OUT before the callback and balance verification. While `nonReentrant` modifier is applied, there's a potential issue with the order of operations.

```solidity
// fillAskOrder - Line 247-259
if (data.length > 0) {
    incProtocolProfits(pair.quote, result.protocolFee);
    uint256 balanceBefore = pair.quote.balanceOfSelf();

    // always transfer ERC20 to msg.sender
    pair.base.transfer(msg.sender, result.filledAmt);  // Transfer OUT first
    IGridCallback(msg.sender)
        .gridFillCallback(
            Currency.unwrap(pair.quote), Currency.unwrap(pair.base), inAmt, result.filledAmt, data
        );
    if (balanceBefore + inAmt > pair.quote.balanceOfSelf()) {
        revert IProtocolErrors.CallbackInsufficientInput();
    }
}
```

**Risk:** Although `nonReentrant` is used, the pattern of transferring tokens out before the callback creates a window where:
1. Tokens are already transferred out
2. If the callback fails after the transfer, state has already been updated
3. The balance check happens after the callback

**Mitigation:** The current implementation is protected by `nonReentrant`, but consider:
1. Following strict CEI pattern - move all transfers after callbacks
2. Or use a two-phase commit pattern

**Status:** Partially mitigated by `nonReentrant` modifier, but architectural improvement recommended.

---

### H-02: Unchecked Return Value in rescueEth

**Location:** [`GridEx.sol`](src/GridEx.sol:563-566)

**Description:** The `rescueEth` function uses a low-level `.call` to transfer ETH but only checks success. If the owner calls this with a malicious contract as `to`, it could lead to unexpected behavior.

```solidity
function rescueEth(address to, uint256 amount) external onlyOwner {
    (bool success,) = to.call{value: amount}("");
    require(success, "ETH transfer failed");
}
```

**Risk:** 
- Owner can drain all ETH from the contract
- No events emitted for this critical operation
- Could be used to bypass normal withdrawal mechanisms

**Mitigation:**
1. Add event emission for transparency
2. Consider adding a timelock for large withdrawals
3. Add a rescue function that follows the same pattern as `withdrawGridProfits`

```solidity
event EthRescued(address indexed to, uint256 amount);

function rescueEth(address to, uint256 amount) external onlyOwner {
    (bool success,) = to.call{value: amount}("");
    require(success, "ETH transfer failed");
    emit EthRescued(to, amount);
}
```

**Status:** Unmitigated - requires code changes.

---

## 3. Medium Severity Findings

### M-01: Missing Reentrancy Protection on cancelGrid and cancelGridOrders

**Location:** [`GridEx.sol`](src/GridEx.sol:495-510), [`GridEx.sol`](src/GridEx.sol:534-546)

**Description:** The `cancelGrid` and `cancelGridOrders` functions do not have the `nonReentrant` modifier, yet they transfer tokens out after state updates.

```solidity
function cancelGrid(address recipient, uint128 gridId, uint32 flag) public override {
    (uint64 pairId, uint256 baseAmt, uint256 quoteAmt) = _gridState.cancelGrid(msg.sender, gridId);
    Pair memory pair = getPairById[pairId];
    if (baseAmt > 0) {
        AssetSettle.transferAssetTo(pair.base, recipient, baseAmt, flag & 0x1);
    }
    // ...
}
```

**Risk:** While the CEI pattern is followed (state updated in `_gridState.cancelGrid` before transfers), the external calls to `transferAssetTo` could potentially call back into the contract. The `transferAssetTo` function can unwrap WETH and transfer ETH:

```solidity
function transferAssetTo(Currency token, address addr, uint256 amount, uint32 flag) internal {
    if (flag == 0) {
        token.transfer(addr, amount);
    } else {
        require(Currency.unwrap(token) == WETH, "Not WETH");
        IWETH(WETH).withdraw(amount);
        safeTransferETH(addr, amount);  // External ETH transfer
    }
}
```

**Mitigation:** Add `nonReentrant` modifier to `cancelGrid` and `cancelGridOrders` functions.

**Status:** Unmitigated.

---

### M-02: Potential Integer Overflow in Accumulated Amounts

**Location:** [`GridOrder.sol`](src/libraries/GridOrder.sol:628-632), [`GridOrder.sol`](src/libraries/GridOrder.sol:653-658)

**Description:** When canceling grids, amounts are accumulated in `uint256` variables without overflow checks:

```solidity
unchecked {
    // Safe: ba and qa are uint128 from storage, sum cannot exceed uint256
    baseAmt += ba;
    quoteAmt += qa;
    ++i;
}
```

**Risk:** While the comment states this is safe because individual amounts are `uint128`, a grid with many orders could theoretically accumulate amounts approaching `uint256` max. The maximum number of orders is bounded by `uint32` (4 billion), but each order amount is `uint128`.

**Calculation:**
- Max orders: 2^32
- Max amount per order: 2^128 - 1
- Max total: 2^32 * (2^128 - 1) = 2^160 - 2^32

This exceeds `uint256` max (2^256 - 1) is not exceeded, but the unchecked block could hide issues if the bounds change.

**Mitigation:** Add explicit overflow checks or use `SafeCast` for the accumulated amounts.

**Status:** Low risk due to practical limits, but recommend explicit checks.

---

### M-03: Strategy Contract Can Manipulate Prices

**Location:** [`GridOrder.sol`](src/libraries/GridOrder.sol:266), [`GridOrder.sol`](src/libraries/GridOrder.sol:276)

**Description:** Strategy contracts are called to get prices during order placement and filling:

```solidity
IGridStrategy(param.askStrategy).createGridStrategy(true, gridId, param.askData);
// ...
uint256 price = IGridStrategy(param.bidStrategy).getPrice(false, gridId, i);
```

**Risk:** A malicious strategy contract could:
1. Return different prices during placement vs filling
2. Return extremely high/low prices to manipulate order amounts
3. Revert unexpectedly to DOS the protocol

**Mitigation:** The protocol uses a whitelist for strategies (`whitelistedStrategies`), which mitigates this risk. However, the whitelist check could be more robust:

```solidity
if (param.askOrderCount > 0) {
    if (!whitelistedStrategies[address(param.askStrategy)]) {
        revert IOrderErrors.StrategyNotWhitelisted();
    }
}
```

**Recommendation:**
1. Ensure thorough auditing of whitelisted strategy contracts
2. Consider adding price bounds validation
3. Add a mechanism to emergency remove strategies from whitelist

**Status:** Mitigated by whitelist, but requires trust in strategy contracts.

---

### M-04: ETH Refund Failure Not Properly Handled

**Location:** [`AssetSettle.sol`](src/AssetSettle.sol:63-68)

**Description:** The `tryPaybackETH` function silently ignores failed ETH transfers:

```solidity
function tryPaybackETH(address to, uint256 value) internal {
    (bool success,) = to.call{value: value}(new bytes(0));
    if (!success) {
        emit RefundFailed(to, value);
    }
}
```

**Risk:** 
- Users may not receive their ETH refunds
- Funds remain stuck in the contract
- Relies on off-chain monitoring to detect failures

**Mitigation:** 
1. Consider allowing users to claim failed refunds later
2. Add a mapping to track failed refunds
3. Provide a `claimFailedRefund` function

**Status:** Partially mitigated by event emission, but user funds could be stuck.

---

### M-05: Missing Input Validation in Multiple Functions

**Location:** Multiple files

**Description:** Several functions lack proper input validation:

1. **[`GridEx.sol:456`](src/GridEx.sol:456)** - `withdrawGridProfits` doesn't validate `to` address:
```solidity
function withdrawGridProfits(uint128 gridId, uint256 amt, address to, uint32 flag) public override {
    // No check for to != address(0)
}
```

2. **[`GridEx.sol:495`](src/GridEx.sol:495)** - `cancelGrid` doesn't validate `recipient`:
```solidity
function cancelGrid(address recipient, uint128 gridId, uint32 flag) public override {
    // No check for recipient != address(0)
}
```

3. **[`Vault.sol:24`](src/Vault.sol:24)** - `withdrawERC20` doesn't validate addresses:
```solidity
function withdrawERC20(address token, address to, uint256 amount) external onlyOwner {
    ERC20(token).safeTransfer(to, amount);
}
```

**Risk:** 
- Transfers to `address(0)` would result in permanent loss of funds
- Invalid token addresses could cause unexpected reverts

**Mitigation:** Add zero address checks:
```solidity
require(to != address(0), "Invalid recipient");
```

**Status:** Unmitigated.

---

## 4. Low Severity Findings

### L-01: Missing Event Emission for Critical Operations

**Location:** Multiple files

**Description:** Several state-changing functions don't emit events:

1. `rescueEth` - No event for ETH rescue
2. `setQuoteToken` - Event is emitted but consider indexing parameters

**Recommendation:** Add events for all critical operations for off-chain monitoring.

---

### L-02: Unbounded Loop in cancelGrid

**Location:** [`GridOrder.sol`](src/libraries/GridOrder.sol:614-634)

**Description:** The `cancelGrid` function iterates through all orders in a grid:

```solidity
for (uint32 i; i < askCount;) {
    // ...
}
```

**Risk:** Grids with many orders could exceed block gas limit, making cancellation impossible.

**Mitigation:** 
1. Add a maximum order count per grid
2. Implement batch cancellation
3. Document the maximum recommended order count

---

### L-03: Unused Variable in fillBidOrders

**Location:** [`GridEx.sol`](src/GridEx.sol:399)

**Description:** Variable `taker` is declared but not used:

```solidity
address taker = msg.sender;
```

**Recommendation:** Remove unused variable or use it consistently.

---

### L-04: Inconsistent Use of SafeCast

**Location:** Multiple files

**Description:** The code uses manual casting with comments instead of `SafeCast` library:

```solidity
// casting to 'uint128' is safe because amt < 1<<128
// forge-lint: disable-next-line(unsafe-typecast)
_gridState.gridConfigs[gridId].profits = conf.profits - uint128(amt);
```

**Recommendation:** Use `SafeCast.toUint128()` for consistency and safety.

---

### L-05: Missing Zero Amount Check in settleAssetWith

**Location:** [`AssetSettle.sol`](src/AssetSettle.sol:79-112)

**Description:** The `settleAssetWith` function doesn't check if `inAmt` or `outAmt` is zero before performing transfers.

**Risk:** Zero amount transfers could waste gas or have unexpected behavior with certain tokens.

---

### L-06: WETH Address Can Be Set Only Once

**Location:** [`GridEx.sol`](src/GridEx.sol:61-73)

**Description:** The `initialize` function can only be called once, but there's no way to update WETH address if needed.

**Risk:** If WETH contract needs to be migrated, the protocol would be stuck.

**Recommendation:** Consider adding an owner-only function to update WETH address with proper safeguards.

---

### L-07: Pair Creation is Permissionless

**Location:** [`Pair.sol`](src/Pair.sol:54-86)

**Description:** The `getOrCreatePair` function is public and anyone can create new trading pairs.

```solidity
function getOrCreatePair(Currency base, Currency quote) public override returns (Pair memory) {
    // Anyone can call this
}
```

**Risk:** 
- Spam creation of pairs could bloat state
- No economic disincentive for pair creation

**Mitigation:** Consider adding a small fee for pair creation or making it permissioned.

---

### L-08: Protocol Fee Can Be Set to Maximum

**Location:** [`GridEx.sol`](src/GridEx.sol:571-575)

**Description:** The owner can set `oneshotProtocolFeeBps` to the maximum (10%) without any timelock or governance.

```solidity
function setOneshotProtocolFeeBps(uint32 feeBps) external onlyOwner {
    // Can be set to MAX_FEE (10%) immediately
}
```

**Recommendation:** Add a timelock or gradual change mechanism for fee adjustments.

---

## 5. Informational Findings

### I-01: Use of Custom Errors

The codebase uses custom errors extensively, which is good for gas optimization. However, ensure all errors are properly documented.

---

### I-02: Solidity Version Consistency

Different files use different Solidity versions:
- `GridEx.sol`: `^0.8.33`
- `SafeCast.sol`: `^0.8.24`
- `Currency.sol`: `^0.8.24`

**Recommendation:** Use a consistent Solidity version across all files.

---

### I-03: Missing NatSpec Documentation

Some functions lack complete NatSpec documentation:
- `getGridOrders`
- `getGridProfits`
- `getGridConfig`

---

### I-04: Test Coverage

Ensure comprehensive test coverage for:
- Edge cases in fee calculations
- ETH wrapping/unwrapping edge cases
- Strategy contract interactions

---

### I-05: Oracle Dependency

The protocol doesn't use external price oracles. Prices are determined by strategy contracts. This is by design but should be documented clearly.

---

### I-06: Upgrade Path

The contract doesn't implement an upgrade mechanism. Consider documenting the upgrade path or lack thereof.

---

## 6. Centralization Risks

### Owner Privileges

The contract owner has significant control:

1. **Pause/Unpause** - Can halt all trading
2. **Strategy Whitelist** - Can add/remove strategies
3. **Quote Token Management** - Can set quote token priorities
4. **Fee Setting** - Can set protocol fees for oneshot orders
5. **ETH Rescue** - Can drain ETH from contract
6. **Vault Ownership** - Owns the vault receiving protocol fees

**Recommendations:**
1. Consider using a timelock for critical operations
2. Implement multi-sig for owner functions
3. Consider gradual decentralization through governance

---

## 7. Gas Optimization

### G-01: Use calldata Instead of memory

**Location:** [`GridOrder.sol`](src/libraries/GridOrder.sol:682)

```solidity
function cancelGridOrders(GridState storage self, address sender, uint128 gridId, uint256[] memory idList)
```

Change `memory` to `calldata` for the array parameter.

---

### G-02: Cache Storage Reads

In loops, cache storage reads to memory:

```solidity
// In cancelGrid, cache gridConf values before loop
uint32 askCount = gridConf.askOrderCount;
uint128 startAskId = gridConf.startAskOrderId;
```

---

### G-03: Use unchecked for Loop Increments

Already implemented in most places, which is good.

---

### G-04: Pack Struct Variables

The `GridConfig` struct could be optimized for storage:

```solidity
struct GridConfig {
    address owner;           // 20 bytes
    // Consider packing smaller values
    uint128 profits;         // 16 bytes
    uint128 baseAmt;         // 16 bytes
    // ...
}
```

---

## 8. Conclusion

The GridEx protocol demonstrates a well-structured implementation of a grid trading system with several security measures in place:

### Strengths
1. Use of `ReentrancyGuard` on critical functions
2. Strategy whitelist for controlling external contract interactions
3. Pausable functionality for emergency situations
4. Use of SafeTransferLib for token transfers
5. Comprehensive error handling with custom errors
6. FullMath for precise calculations

### Areas for Improvement
1. Add `nonReentrant` to cancellation functions
2. Add zero address validation
3. Improve event emission for critical operations
4. Consider timelock for owner functions
5. Add explicit overflow checks in accumulation loops
6. Document maximum order counts to prevent gas limit issues

### Risk Summary
- **No critical vulnerabilities** that could lead to immediate fund loss
- **Two high-severity issues** related to reentrancy patterns and rescue functions
- **Five medium-severity issues** that should be addressed before mainnet deployment
- **Multiple low-severity and informational issues** for code quality improvement

### Recommendations
1. Address all high and medium severity findings before deployment
2. Implement comprehensive monitoring for failed ETH refunds
3. Consider formal verification for critical math operations
4. Conduct additional testing with edge cases
5. Consider a bug bounty program post-deployment

---

**Audit completed.** This report should be used as a starting point for improving the security posture of the GridEx protocol.
