# GridEx Protocol Security Audit Report

**Audit Date:** 2026-02-13  
**Auditor:** AI Security Review  
**Version:** Based on commit at audit time  
**Solidity Version:** ^0.8.33

---

## Executive Summary

This security audit covers the GridEx Protocol, a decentralized grid trading system on Ethereum. The protocol consists of the following main components:

- **GridEx.sol** - Main contract for grid order placement, filling, and cancellation
- **Pair.sol** - Trading pair management
- **Vault.sol** - Protocol fee vault
- **AssetSettle.sol** - Asset settlement and transfers
- **GridOrder.sol** - Grid order state management library
- **Lens.sol** - Price and fee calculation library
- **Linear.sol** - Linear pricing strategy implementation

### Overall Risk Assessment: **MEDIUM**

The protocol demonstrates good security practices with proper use of reentrancy guards, access controls, and overflow protection. However, several areas require attention.

---

## Detailed Findings

### 1. REENTRANCY PROTECTION ✅ PASSED

**Status:** PROTECTED

The protocol correctly implements reentrancy protection:

- [`GridEx.sol`](src/GridEx.sol:27) inherits from `ReentrancyGuard` from solmate
- All fill functions use `nonReentrant` modifier:
  - [`fillAskOrder()`](src/GridEx.sol:232) - Line 232
  - [`fillAskOrders()`](src/GridEx.sol:282) - Line 282
  - [`fillBidOrder()`](src/GridEx.sol:351) - Line 351
  - [`fillBidOrders()`](src/GridEx.sol:394) - Line 394
  - [`withdrawGridProfits()`](src/GridEx.sol:464) - Line 464
  - [`cancelGrid()`](src/GridEx.sol:503) - Line 503
  - [`cancelGridOrders()`](src/GridEx.sol:545) - Line 545

**Note:** The callback pattern in fill functions follows Checks-Effects-Interactions:
1. State is updated first via `_gridState.fillAskOrder()` / `_gridState.fillBidOrder()`
2. Then external calls are made via callback or asset transfer

---

### 2. ACCESS CONTROL ✅ PASSED

**Status:** PROPERLY IMPLEMENTED

The protocol implements multiple layers of access control:

#### Owner-Only Functions (via `Owned` from solmate):
- [`initialize()`](src/GridEx.sol:61) - WETH/USD setup
- [`setQuoteToken()`](src/GridEx.sol:565) - Quote token management
- [`rescueEth()`](src/GridEx.sol:575) - ETH rescue
- [`setOneshotProtocolFeeBps()`](src/GridEx.sol:583) - Fee configuration
- [`pause()`](src/GridEx.sol:598) / [`unpause()`](src/GridEx.sol:604) - Emergency controls
- [`setStrategyWhitelist()`](src/GridEx.sol:609) - Strategy whitelist

#### Grid Owner-Only Functions:
- [`cancelGrid()`](src/GridEx.sol:503) - Validates `sender == gridConf.owner`
- [`cancelGridOrders()`](src/GridEx.sol:545) - Validates ownership
- [`modifyGridFee()`](src/GridEx.sol:498) - Validates ownership
- [`withdrawGridProfits()`](src/GridEx.sol:464) - Validates ownership

#### Strategy Whitelist:
- [`placeGridOrders()`](src/GridEx.sol:143) validates strategies are whitelisted before use
- Only owner can modify whitelist via [`setStrategyWhitelist()`](src/GridEx.sol:609)

---

### 3. INTEGER OVERFLOW/UNDERFLOW ✅ PASSED

**Status:** PROTECTED

The protocol uses Solidity ^0.8.33 which has built-in overflow/underflow protection. Additional safeguards:

#### SafeCast Library:
- [`SafeCast.sol`](src/libraries/SafeCast.sol) provides safe casting functions
- Used throughout the codebase for type conversions

#### FullMath Library:
- [`FullMath.sol`](src/libraries/FullMath.sol) provides 512-bit precision math
- Prevents overflow in multiplication/division operations
- Used in [`Lens.sol`](src/libraries/Lens.sol:22) for price calculations

#### Manual Checks:
- [`Lens.sol:30-32`](src/libraries/Lens.sol:30) - Validates quote amount doesn't exceed uint128
- [`Lens.sol:77-79`](src/libraries/Lens.sol:77) - Validates base amount doesn't exceed uint128
- [`GridEx.sol:480-482`](src/GridEx.sol:480) - Validates amount < 2^128 before casting

#### Unchecked Blocks:
The codebase uses `unchecked` blocks appropriately where overflow is mathematically impossible:
- Loop increments
- Calculations where bounds are already verified

---

### 4. FRONT-RUNNING ⚠️ MEDIUM RISK

**Status:** PARTIALLY MITIGATED

#### Observations:

1. **Slippage Protection:** Fill functions include `minAmt` parameter for slippage protection:
   - [`fillAskOrder()`](src/GridEx.sol:237) - Line 237
   - [`fillBidOrder()`](src/GridEx.sol:356) - Line 356

2. **No Commit-Reveal:** Orders are placed directly without commit-reveal, which could expose strategies to MEV.

3. **Public Mempool Visibility:** Grid order parameters are visible in mempool before inclusion.

#### Recommendations:
- Consider implementing a commit-reveal scheme for large orders
- Document MEV risks for users
- Consider using private mempool services for sensitive operations

---

### 5. CALLBACK SECURITY ⚠️ MEDIUM RISK

**Status:** NEEDS ATTENTION

The protocol uses a callback pattern for flash-swap style fills:

#### Current Implementation:
```solidity
// GridEx.sol:253-259
IGridCallback(msg.sender).gridFillCallback(
    Currency.unwrap(pair.quote), Currency.unwrap(pair.base), inAmt, result.filledAmt, data
);
if (balanceBefore + inAmt > pair.quote.balanceOfSelf()) {
    revert IProtocolErrors.CallbackInsufficientInput();
}
```

#### Security Measures:
- Balance check after callback ensures proper payment
- Callback is made to `msg.sender` only (not arbitrary address)

#### Risks:
1. **Reentrancy via Callback:** Although `nonReentrant` protects against this, malicious callbacks could still attempt various attacks
2. **Gas Limit Manipulation:** Callbacks could consume excessive gas
3. **Callback Failure:** If callback reverts, the entire transaction reverts

#### Recommendations:
- Document callback requirements clearly
- Consider gas limits for callbacks
- Ensure callback contracts are well-audited

---

### 6. PAUSE MECHANISM ✅ PASSED

**Status:** PROPERLY IMPLEMENTED

The protocol implements emergency pause functionality:

- [`Pausable.sol`](src/utils/Pausable.sol) provides pause/unpause logic
- [`pause()`](src/GridEx.sol:598) and [`unpause()`](src/GridEx.sol:604) are owner-only
- Trading functions use `whenNotPaused` modifier:
  - [`placeGridOrders()`](src/GridEx.sol:146)
  - [`placeETHGridOrders()`](src/GridEx.sol:116)
  - [`fillAskOrder()`](src/GridEx.sol:233)
  - [`fillAskOrders()`](src/GridEx.sol:282)
  - [`fillBidOrder()`](src/GridEx.sol:352)
  - [`fillBidOrders()`](src/GridEx.sol:394)

**Good Practice:** Cancellation and withdrawal remain available when paused, allowing users to exit.

---

### 7. INPUT VALIDATION ✅ PASSED

**Status:** COMPREHENSIVE

The protocol implements thorough input validation:

#### Address Validation:
- [`GridEx.sol:50-51`](src/GridEx.sol:50) - Owner and vault address validation
- [`GridEx.sol:63-64`](src/GridEx.sol:63) - WETH and USD address validation
- [`GridEx.sol:610`](src/GridEx.sol:610) - Strategy address validation

#### Amount Validation:
- [`GridOrder.sol:92-94`](src/libraries/GridOrder.sol:92) - At least one order required
- [`GridOrder.sol:98-100`](src/libraries/GridOrder.sol:98) - Fee range validation (MIN_FEE to MAX_FEE)
- [`GridOrder.sol:110-112`](src/libraries/GridOrder.sol:110) - Total base amount overflow check
- [`GridEx.sol:132,136`](src/GridEx.sol:132) - ETH amount validation

#### Strategy Validation:
- [`Linear.sol:82-143`](src/strategy/Linear.sol:82) - Comprehensive parameter validation
- Price and gap validation for both ask and bid orders
- Zero quote amount prevention

#### Pair Validation:
- [`Pair.sol:61-73`](src/Pair.sol:61) - Quote token priority validation
- Token order validation for same-priority tokens

---

### 8. EVENT EMISSION ✅ PASSED

**Status:** COMPREHENSIVE

The protocol emits events for all critical operations:

#### Order Events:
- [`GridOrderCreated`](src/GridEx.sol:197) - Emitted on order placement
- [`FilledOrder`](src/GridEx.sol:241) - Emitted on each fill
- [`CancelWholeGrid`](src/GridEx.sol:517) - Emitted on grid cancellation
- [`CancelGridOrder`](src/libraries/GridOrder.sol:724) - Emitted on individual order cancellation

#### Admin Events:
- [`QuotableTokenUpdated`](src/GridEx.sol:568) - Quote token changes
- [`OneshotProtocolFeeChanged`](src/GridEx.sol:586) - Fee changes
- [`StrategyWhitelistUpdated`](src/GridEx.sol:612) - Strategy whitelist changes
- [`Paused`](src/utils/Pausable.sol:15) / [`Unpaused`](src/utils/Pausable.sol:18) - Pause state changes

#### Other Events:
- [`PairCreated`](src/Pair.sol:83) - New trading pair creation
- [`WithdrawProfit`](src/GridEx.sol:494) - Profit withdrawal
- [`RefundFailed`](src/AssetSettle.sol:24) - Failed ETH refund (for off-chain reconciliation)

---

### 9. FEE CALCULATION ✅ PASSED

**Status:** CORRECT IMPLEMENTATION

Fee calculations in [`Lens.sol`](src/libraries/Lens.sol):

#### Standard Orders (75% LP / 25% Protocol):
```solidity
// Lens.sol:124-129
function calculateFees(uint128 vol, uint32 bps) public pure returns (uint128 lpFee, uint128 protocolFee) {
    uint128 fee = uint128((uint256(vol) * uint256(bps)) / 1000000);
    protocolFee = fee >> 2;  // 25%
    lpFee = fee - protocolFee;  // 75%
}
```

#### Oneshot Orders (25% Maker / 75% Protocol):
```solidity
// Lens.sol:138-143
function calculateOneshotFee(uint128 vol, uint32 bps) public pure returns (uint128 lpFee, uint128 protocolFee) {
    uint128 fee = uint128((uint256(vol) * uint256(bps)) / 1000000);
    lpFee = fee >> 2;  // 25% to maker as profit
    protocolFee = fee - lpFee;  // 75% to protocol
}
```

#### Fee Bounds:
- MIN_FEE = 10 (0.001%)
- MAX_FEE = 100000 (10%)

---

### 10. ETH HANDLING ⚠️ MEDIUM RISK

**Status:** NEEDS ATTENTION

The protocol handles both native ETH and WETH:

#### Current Implementation:

1. **ETH Refunds:** Uses `tryPaybackETH()` which doesn't revert on failure:
   ```solidity
   // AssetSettle.sol:63-68
   function tryPaybackETH(address to, uint256 value) internal {
       (bool success,) = to.call{value: value}(new bytes(0));
       if (!success) {
           emit RefundFailed(to, value);
       }
   }
   ```

2. **ETH Rescue:** Owner can rescue stuck ETH via [`rescueEth()`](src/GridEx.sol:575)

3. **WETH Wrapping/Unwrapping:** Handled in [`AssetSettle.sol`](src/AssetSettle.sol):

#### Risks:
1. **Stuck ETH:** If `tryPaybackETH` fails, ETH remains in contract
2. **Reentrancy via ETH Transfer:** ETH transfers can trigger fallback functions
3. **WETH Centralization:** WETH contract is trusted

#### Mitigations:
- `RefundFailed` event allows off-chain tracking
- `rescueEth()` provides recovery mechanism
- `nonReentrant` protects against reentrancy

---

### 11. STRATEGY CONTRACT RISK ⚠️ MEDIUM RISK

**Status:** MITIGATED BY WHITELIST

The protocol allows custom pricing strategies:

#### Security Measures:
1. **Whitelist:** Only owner-approved strategies can be used
2. **Interface Enforcement:** Strategies must implement [`IGridStrategy`](src/interfaces/IGridStrategy.sol)
3. **Validation:** Strategies must implement `validateParams()` for parameter checking

#### Risks:
1. **Malicious Strategy:** A whitelisted strategy could:
   - Return manipulated prices
   - Cause unexpected behavior
   - Consume excessive gas

2. **Strategy Bugs:** Even well-intentioned strategies may have bugs

#### Recommendations:
- Thoroughly audit all strategies before whitelisting
- Implement strategy upgrade governance
- Consider strategy gas limits

---

### 12. VAULT SECURITY ✅ PASSED

**Status:** SIMPLE AND SECURE

[`Vault.sol`](src/Vault.sol) is a simple, secure implementation:

- Owner-only withdrawals
- Supports both ERC20 and ETH
- No complex logic
- Uses `SafeTransferLib` for token transfers

---

## Gas Optimization Findings

### 1. Storage Packing Opportunities

**Current:** [`GridOrder.sol:51-73`](src/libraries/GridOrder.sol:51)
The `GridState` struct could benefit from tighter packing:
- Consider reordering fields to minimize storage slots

### 2. Unchecked Blocks Usage ✅

The codebase appropriately uses `unchecked` for:
- Loop increments (no overflow risk)
- Calculations with verified bounds

### 3. Calldata Usage ✅

Functions appropriately use `calldata` for external parameters:
- [`GridEx.sol:143`](src/GridEx.sol:143) - `placeGridOrders` uses calldata
- [`GridOrder.sol:90`](src/libraries/GridOrder.sol:90) - `validateGridOrderParam` uses calldata

---

## Code Quality Observations

### Positive Aspects:
1. **Comprehensive Documentation:** Well-documented functions with NatSpec
2. **Custom Errors:** Uses custom errors for gas efficiency
3. **Consistent Style:** Follows Solidity best practices
4. **Test Coverage:** Extensive test suite in `/test` directory
5. **Linting:** Uses forge-lint with appropriate disable comments

### Areas for Improvement:
1. **Magic Numbers:** Some constants could be named (e.g., fee denominators)
2. **Complex Logic:** Some functions are complex and could be broken down
3. **Error Messages:** Some errors could include more context

---

## Summary of Findings

| Category | Status | Severity |
|----------|--------|----------|
| Reentrancy | ✅ Protected | N/A |
| Access Control | ✅ Proper | N/A |
| Integer Overflow | ✅ Protected | N/A |
| Front-running | ⚠️ Partial | Medium |
| Callback Security | ⚠️ Attention | Medium |
| Pause Mechanism | ✅ Proper | N/A |
| Input Validation | ✅ Comprehensive | N/A |
| Event Emission | ✅ Comprehensive | N/A |
| Fee Calculation | ✅ Correct | N/A |
| ETH Handling | ⚠️ Attention | Medium |
| Strategy Risk | ⚠️ Mitigated | Medium |
| Vault Security | ✅ Secure | N/A |

---

## Recommendations

### High Priority:
1. Document MEV/front-running risks for users
2. Implement gas limits for callbacks
3. Add comprehensive integration tests for callback scenarios

### Medium Priority:
1. Consider commit-reveal for large orders
2. Implement strategy upgrade governance
3. Add more granular pause controls

### Low Priority:
1. Improve error messages with context
2. Add more inline documentation for complex calculations
3. Consider using named constants for magic numbers

---

## Conclusion

The GridEx Protocol demonstrates strong security practices with proper reentrancy protection, access controls, and input validation. The main areas of concern are:

1. **Front-running exposure** - Inherent to DEX designs, partially mitigated by slippage protection
2. **Callback security** - Well-protected but requires careful integration by users
3. **Strategy risk** - Mitigated by whitelist but requires ongoing governance

The protocol is suitable for production deployment with the recommended considerations. Users should be made aware of the risks associated with callbacks and MEV exposure.

---

**Disclaimer:** This audit was performed by an AI system and should not be considered a substitute for a professional security audit. The findings and recommendations are based on code analysis at the time of review and may not cover all possible vulnerabilities or attack vectors.
