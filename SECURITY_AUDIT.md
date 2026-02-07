# GridEx Security Audit Report

**Project:** GridEx - Grid Trading Exchange  
**Version:** Solidity 0.8.28  
**Audit Date:** February 2026 (Re-audit)  
**Auditor:** Security Review  

---

## Executive Summary

GridEx is a decentralized grid trading exchange built on Solidity that allows makers to place grid orders at multiple price levels and takers to fill them. The system supports both ERC20 tokens and native ETH (via WETH wrapping), with configurable fee structures and compound/non-compound order modes.

This re-audit reflects significant improvements from the previous audit. Several critical and high-severity issues have been resolved. The current audit identified **0 Critical**, **0 High**, **2 Medium**, **4 Low**, and **5 Informational** findings.

### Previous Issues Status

| Issue | Severity | Status |
|-------|----------|--------|
| C-01: SEA.sol Signature Verification | Critical | ✅ **Resolved** - Contract removed |
| C-02: Linear.sol No Access Control | Critical | ✅ **Resolved** - Added `onlyGridEx` modifier |
| H-01: modifyGridFee No Fee Validation | High | ✅ **Resolved** - Added MIN_FEE/MAX_FEE validation |
| H-02: Vault.sol No Withdrawal Mechanism | High | ✅ **Resolved** - Added withdrawal functions |
| H-03: Pair.getOrCreatePair Public | High | ✅ **Not Applicable** - Permissionless DEX by design |
| M-02: FlashLoan.sol Dead Code | Medium | ✅ **Resolved** - Contract removed |

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Medium Findings](#medium-findings)
3. [Low Findings](#low-findings)
4. [Informational Findings](#informational-findings)
5. [Test Coverage Analysis](#test-coverage-analysis)
6. [Recommendations](#recommendations)

---

## Architecture Overview

### Core Contracts

| Contract | Description | Lines |
|----------|-------------|-------|
| [`GridEx.sol`](src/GridEx.sol) | Main exchange contract handling order placement, filling, and cancellation | 702 |
| [`Pair.sol`](src/Pair.sol) | Abstract contract managing trading pairs | 68 |
| [`AssetSettle.sol`](src/AssetSettle.sol) | Handles token/ETH settlement and transfers | 100 |
| [`Vault.sol`](src/Vault.sol) | Protocol fee vault with withdrawal functions | 24 |
| [`GridOrder.sol`](src/libraries/GridOrder.sol) | Library containing grid order state and logic | 568 |
| [`Linear.sol`](src/strategy/Linear.sol) | Linear price strategy implementation | 142 |

### Key Design Patterns

- **Grid Order System**: Makers place orders at multiple price levels; orders flip between ask/bid states when filled
- **Strategy Pattern**: External strategy contracts (IGridStrategy) calculate prices with access control
- **Callback Pattern**: Flash-swap style fills via IGridCallback
- **ReentrancyGuard**: Applied to all fill functions
- **Protocol Fees**: 60% protocol / 40% LP fee split, sent directly to vault
- **Checks-Effects-Interactions**: Properly followed in most functions

### Security Features Implemented

1. **ReentrancyGuard** on all fill functions ([`GridEx.sol:213`](src/GridEx.sol:213), [`GridEx.sol:289`](src/GridEx.sol:289), [`GridEx.sol:385`](src/GridEx.sol:385), [`GridEx.sol:451`](src/GridEx.sol:451))
2. **Access Control** via Owned pattern for admin functions
3. **Strategy Access Control** via `onlyGridEx` modifier ([`Linear.sol:18-21`](src/Linear.sol:18))
4. **Fee Validation** with MIN_FEE/MAX_FEE bounds ([`GridOrder.sol:560-562`](src/libraries/GridOrder.sol:560))
5. **Safe Math** via Solidity 0.8.28 built-in overflow checks
6. **SafeTransferLib** for ERC20 transfers

---

## Medium Findings

### [M-01] Callback Pattern Allows Arbitrary External Calls

**Severity:** Medium  
**Location:** [`src/GridEx.sol:252-258`](src/GridEx.sol:252), [`src/GridEx.sol:353-359`](src/GridEx.sol:353), [`src/GridEx.sol:417-423`](src/GridEx.sol:417), [`src/GridEx.sol:513-519`](src/GridEx.sol:513)

**Description:**

The fill functions allow callers to provide callback data, which triggers an external call to `msg.sender`:

```solidity
if (data.length > 0) {
    incProtocolProfits(pair.quote, result.protocolFee);
    uint256 balanceBefore = pair.quote.balanceOfSelf();

    // always transfer ERC20 to msg.sender
    pair.base.transfer(msg.sender, result.filledAmt);
    IGridCallback(msg.sender).gridFillCallback(
        Currency.unwrap(pair.quote),
        Currency.unwrap(pair.base),
        inAmt,
        result.filledAmt,
        data
    );
    require(balanceBefore + inAmt <= pair.quote.balanceOfSelf(), "G1");
}
```

**Mitigating Factors:**

1. ReentrancyGuard prevents re-entry
2. Balance check after callback ensures payment
3. Tokens transferred before callback (not after)

**Impact:**

- Callback receiver can perform arbitrary operations before balance check
- Could interact with other protocols in unexpected ways
- Potential for complex attack vectors if combined with other vulnerabilities

**Recommendation:**

Document the security assumptions clearly. Consider implementing a whitelist for callback receivers in high-security deployments.

---

### [M-02] tryPaybackETH Silently Fails

**Severity:** Medium  
**Location:** [`src/AssetSettle.sol:39-42`](src/AssetSettle.sol:39)

**Description:**

The [`tryPaybackETH()`](src/AssetSettle.sol:39) function silently ignores failed ETH transfers:

```solidity
function tryPaybackETH(address to, uint256 value) internal {
    (bool success,) = to.call{value: value}(new bytes(0));
    success;  // Intentionally ignored
}
```

**Impact:**

- If a user's contract cannot receive ETH, the refund is lost
- Users may not realize they didn't receive their refund
- ETH accumulates in the contract (can be rescued via `rescueETH`)

**Recommendation:**

Consider implementing a pull pattern for refunds:

```solidity
mapping(address => uint256) public pendingRefunds;

function tryPaybackETH(address to, uint256 value) internal {
    (bool success,) = to.call{value: value}("");
    if (!success) {
        pendingRefunds[to] += value;
        emit RefundPending(to, value);
    }
}

function claimRefund() external {
    uint256 amount = pendingRefunds[msg.sender];
    require(amount > 0, "No refund");
    pendingRefunds[msg.sender] = 0;
    (bool success,) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");
}
```

---


## Low Findings

### [L-01] Missing Event Emission for Quote Token Removal

**Severity:** Low  
**Location:** [`src/GridEx.sol:661-668`](src/GridEx.sol:661)

**Description:**

The [`setQuoteToken()`](src/GridEx.sol:661) function emits `QuotableTokenUpdated` for both adding and removing tokens (priority=0), but there's no distinction:

```solidity
function setQuoteToken(
    Currency token,
    uint256 priority
) external override onlyOwner {
    quotableTokens[token] = priority;
    emit QuotableTokenUpdated(token, priority);
}
```

**Recommendation:**

Consider adding a separate event for token removal or documenting that priority=0 means removal.

---

### [L-02] Unchecked Arithmetic in Multiple Locations

**Severity:** Low  
**Location:** Multiple files

**Description:**

Several `unchecked` blocks are used for gas optimization:

- [`src/libraries/GridOrder.sol:482-485`](src/libraries/GridOrder.sol:482) - cancelGrid loop
- [`src/libraries/GridOrder.sol:500-503`](src/libraries/GridOrder.sol:500) - cancelGrid loop
- [`src/libraries/GridOrder.sol:543-546`](src/libraries/GridOrder.sol:543) - cancelGridOrders loop

While these appear safe due to prior validation (amounts come from order storage), unchecked arithmetic always carries risk.

**Recommendation:**

Add comments explaining why overflow is impossible in each case. Example:

```solidity
unchecked {
    // Safe: ba and qa are uint128 from storage, sum cannot exceed uint256
    baseAmt += ba;
    quoteAmt += qa;
}
```

---

### [L-03] Assert Statements Used for Validation

**Severity:** Low  
**Location:** [`src/AssetSettle.sol:59`](src/AssetSettle.sol:59), [`src/AssetSettle.sol:70`](src/AssetSettle.sol:70), [`src/AssetSettle.sol:83`](src/AssetSettle.sol:83)

**Description:**

`assert()` is used for validation that could fail due to user input:

```solidity
assert(Currency.unwrap(inToken) == WETH);  // Line 59
assert(Currency.unwrap(outToken) == WETH); // Line 70
assert(Currency.unwrap(token) == WETH);    // Line 83
```

**Impact:**

- `assert()` consumes all remaining gas on failure
- Should be reserved for invariant checks, not input validation

**Recommendation:**

Replace with `require()` statements:

```solidity
require(Currency.unwrap(inToken) == WETH, "Not WETH");
```

---

### [L-04] Potential Precision Loss in Fee Calculation

**Severity:** Low  
**Location:** [`src/libraries/Lens.sol:98-104`](src/libraries/Lens.sol:98)

**Description:**

Fee calculation may lose precision due to integer division:

```solidity
function calculateFees(uint128 vol, uint32 bps) public pure returns (uint128 lpFee, uint128 protocolFee) {
    unchecked {
        uint128 fee = uint128((uint256(vol) * uint256(bps)) / 1000000);
        protocolFee = fee * 60 / 100;  // Potential precision loss
        lpFee = fee - protocolFee;
    }
}
```

**Impact:**

- Small amounts may result in 0 fees
- Rounding always favors LP (lpFee = fee - protocolFee)

**Recommendation:**

This is acceptable behavior but should be documented. Consider using `mulDiv` for more precise calculations if needed.

---

## Informational Findings

### [I-01] Commented Out Code Throughout Codebase

**Severity:** Informational  
**Location:** Multiple files

**Description:**

Significant amounts of commented-out code exist:
- [`src/GridEx.sol:671-691`](src/GridEx.sol:671) - collectProtocolFee function
- Various commented imports and old implementations

**Recommendation:**

Remove commented code before production deployment. Use version control for history.

---

### [I-02] Inconsistent Error Handling

**Severity:** Informational  
**Location:** Multiple files

**Description:**

Mix of error handling styles:
- Custom errors: `revert IOrderErrors.InvalidParam()`
- Require with strings: `require(condition, "G1")`
- Assert: `assert(Currency.unwrap(token) == WETH)`

**Recommendation:**

Standardize on custom errors for gas efficiency and clarity. Replace all `require(condition, "XX")` with custom errors.

---

### [I-03] Magic Numbers in Code

**Severity:** Informational  
**Location:** Multiple files

**Description:**

Several magic numbers without named constants:
- `1 << 20`, `1 << 19` in quotableTokens priority ([`GridEx.sol:46-48`](src/GridEx.sol:46))
- `0x80000000000000000000000000000000` for ask order mask ([`GridOrder.sol:16`](src/libraries/GridOrder.sol:16))
- `60` and `100` in fee split calculation ([`Lens.sol:101-102`](src/libraries/Lens.sol:101))

**Recommendation:**

Define named constants for all magic numbers:

```solidity
uint256 public constant USD_PRIORITY = 1 << 20;
uint256 public constant WETH_PRIORITY = 1 << 19;
uint256 public constant PROTOCOL_FEE_PERCENT = 60;
uint256 public constant LP_FEE_PERCENT = 40;
```

---

### [I-04] Missing NatSpec Documentation

**Severity:** Informational  
**Location:** Multiple files

**Description:**

Many functions lack NatSpec documentation, particularly:
- Internal/private functions in GridEx.sol
- Library functions in GridOrder.sol
- Strategy contract functions in Linear.sol

**Recommendation:**

Add comprehensive NatSpec documentation for all public and external functions.

---

### [I-05] Gas Optimization Opportunities

**Severity:** Informational  
**Location:** Multiple files

**Description:**

1. **Storage reads in loops**: [`cancelGrid()`](src/libraries/GridOrder.sol:454) could cache more values
2. **Memory vs calldata**: Some functions use `memory` where `calldata` would be more efficient (e.g., [`cancelGridOrders`](src/GridEx.sol:627) uses `memory` for `idList`)
3. **Redundant checks**: Some validation is performed multiple times

**Recommendation:**

Consider gas optimization pass before mainnet deployment.

---

## Test Coverage Analysis

### Covered Scenarios

| Test File | Coverage | Tests |
|-----------|----------|-------|
| [`GridEx.place.t.sol`](test/GridEx.place.t.sol) | Order placement (ERC20, ETH, WETH) | 8 |
| [`GridEx.fill.t.sol`](test/GridEx.fill.t.sol) | Ask/bid order filling | 6 |
| [`GridEx.fillCompound.t.sol`](test/GridEx.fillCompound.t.sol) | Compound order filling | 6 |
| [`GridEx.fillETH.t.sol`](test/GridEx.fillETH.t.sol) | ETH base token fills | 6 |
| [`GridEx.fillETHQuote.t.sol`](test/GridEx.fillETHQuote.t.sol) | ETH quote token fills | 4 |
| [`GridEx.cancel.t.sol`](test/GridEx.cancel.t.sol) | Order cancellation | 9 |
| [`GridEx.cancelETH.t.sol`](test/GridEx.cancelETH.t.sol) | ETH order cancellation | 8 |
| [`GridEx.profit.t.sol`](test/GridEx.profit.t.sol) | Profit withdrawal | 1 |
| [`GridEx.revert.t.sol`](test/GridEx.revert.t.sol) | Error conditions | 4 |

**Total: 52 tests passing**

### Missing Test Coverage

1. **Vault.sol**: No tests for withdrawal functions
2. **Linear.sol**: No direct tests for strategy validation edge cases
3. **modifyGridFee**: No tests for fee modification (function exists but not exposed in GridEx)
4. **Callback pattern**: Limited testing of callback scenarios
5. **Edge cases**: 
   - Maximum order counts
   - Minimum amounts
   - Fee boundary conditions
   - Pair creation edge cases
   - Failed ETH refunds

### Recommendations for Test Improvement

1. Add fuzz tests for arithmetic operations
2. Add invariant tests for token conservation
3. Test all error conditions explicitly
4. Add integration tests with real token contracts
5. Test callback pattern with malicious receivers
6. Add tests for Vault withdrawal functions

---

## Recommendations

### Immediate Actions (Pre-Deployment)

1. **Consider M-03**: Add maximum order count validation
2. **Fix L-03**: Replace `assert()` with `require()` in AssetSettle.sol
3. **Clean up**: Remove commented code

### Short-Term Improvements

1. Consider access control for pair creation (H-01) or document as design decision
2. Implement pull pattern for ETH refunds (M-02)
3. Standardize error handling to custom errors
4. Add comprehensive NatSpec documentation

### Long-Term Improvements

1. Add comprehensive test coverage for edge cases
2. Consider formal verification for core math
3. Gas optimization pass
4. Consider upgradeability pattern for future improvements

---

## Security Checklist

| Check | Status |
|-------|--------|
| Reentrancy protection | ✅ ReentrancyGuard on all fill functions |
| Integer overflow/underflow | ✅ Solidity 0.8.28 built-in checks |
| Access control | ✅ Owned pattern, onlyGridEx modifier |
| Input validation | ✅ Comprehensive validation |
| External calls at end | ⚠️ Callback pattern transfers first |
| Check return values | ✅ SafeTransferLib used |
| No tx.origin | ✅ Not used |
| Event emission | ✅ Events for all state changes |
| Emergency stop | ❌ No pause mechanism |
| Upgrade mechanism | ❌ Not upgradeable |

---

## Conclusion

The GridEx protocol has significantly improved since the previous audit. Critical vulnerabilities have been addressed:

- SEA.sol and FlashLoan.sol removed (eliminating C-01 and M-02)
- Linear.sol now has proper access control (C-02 fixed)
- modifyGridFee now validates fee bounds (H-01 fixed)
- Vault.sol now has withdrawal functions (H-02 fixed)

The remaining findings are primarily medium and low severity, with the most significant being:
- Public pair creation (H-01) - acknowledged design decision
- Callback pattern risks (M-01) - mitigated by ReentrancyGuard
- Silent ETH refund failures (M-02) - can be rescued by owner

The codebase demonstrates good security practices including ReentrancyGuard usage, safe transfer libraries, and proper access control. With the recommended improvements, the protocol should be ready for production deployment.

---

## Disclaimer

This audit report is not a guarantee of security. Smart contract security is a continuous process, and new vulnerabilities may be discovered after this audit. The findings in this report are based on the code reviewed at the time of the audit and may not reflect subsequent changes.

---

**End of Report**
