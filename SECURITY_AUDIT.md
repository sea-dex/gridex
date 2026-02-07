# GridEx Security Audit Report

**Project:** GridEx - Grid Trading Exchange  
**Version:** Solidity 0.8.33  
**Audit Date:** February 2026 (Re-audit v2)  
**Auditor:** Security Review  

---

## Executive Summary

GridEx is a decentralized grid trading exchange built on Solidity that allows makers to place grid orders at multiple price levels and takers to fill them. The system supports both ERC20 tokens and native ETH (via WETH wrapping), with configurable fee structures and compound/non-compound order modes.

This re-audit reflects significant improvements from previous audits. The codebase demonstrates mature security practices with proper access control, reentrancy protection, and comprehensive input validation. The current audit identified **0 Critical**, **0 High**, **1 Medium**, **3 Low**, and **4 Informational** findings.

### Previous Issues Status

| Issue | Severity | Status |
|-------|----------|--------|
| C-01: SEA.sol Signature Verification | Critical | ✅ **Resolved** - Contract removed |
| C-02: Linear.sol No Access Control | Critical | ✅ **Resolved** - Added `onlyGridEx` modifier |
| H-01: modifyGridFee No Fee Validation | High | ✅ **Resolved** - Added MIN_FEE/MAX_FEE validation |
| H-02: Vault.sol No Withdrawal Mechanism | High | ✅ **Resolved** - Added withdrawal functions |
| H-03: Pair.getOrCreatePair Public | High | ✅ **Not Applicable** - Permissionless DEX by design |
| M-01: Callback Pattern Risks | Medium | ✅ **Mitigated** - ReentrancyGuard + balance checks |
| M-02: FlashLoan.sol Dead Code | Medium | ✅ **Resolved** - Contract removed |
| M-03: tryPaybackETH Silently Fails | Medium | ⚠️ **Acknowledged** - rescueEth function added |
| L-03: Assert Statements Used | Low | ✅ **Resolved** - Replaced with require() |

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
| [`GridEx.sol`](src/GridEx.sol) | Main exchange contract handling order placement, filling, and cancellation | 664 |
| [`Pair.sol`](src/Pair.sol) | Abstract contract managing trading pairs | 84 |
| [`AssetSettle.sol`](src/AssetSettle.sol) | Handles token/ETH settlement and transfers | 141 |
| [`Vault.sol`](src/Vault.sol) | Protocol fee vault with withdrawal functions | 39 |
| [`GridOrder.sol`](src/libraries/GridOrder.sol) | Library containing grid order state and logic | 676 |
| [`Linear.sol`](src/strategy/Linear.sol) | Linear price strategy implementation | 171 |
| [`Lens.sol`](src/libraries/Lens.sol) | Price calculation utilities | 131 |
| [`Currency.sol`](src/libraries/Currency.sol) | Custom type for ETH/ERC20 handling | 168 |

### Key Design Patterns

- **Grid Order System**: Makers place orders at multiple price levels; orders flip between ask/bid states when filled
- **Strategy Pattern**: External strategy contracts (IGridStrategy) calculate prices with access control
- **Callback Pattern**: Flash-swap style fills via IGridCallback with balance verification
- **ReentrancyGuard**: Applied to all fill functions
- **Protocol Fees**: 75% LP / 25% protocol fee split (using bit shift `>> 2`)
- **Checks-Effects-Interactions**: Properly followed in all functions

### Security Features Implemented

1. **ReentrancyGuard** on all fill functions ([`GridEx.sol:229`](src/GridEx.sol:229), [`GridEx.sol:295`](src/GridEx.sol:295), [`GridEx.sol:377`](src/GridEx.sol:377), [`GridEx.sol:439`](src/GridEx.sol:439))
2. **Access Control** via Owned pattern for admin functions
3. **Strategy Access Control** via `onlyGridEx` modifier ([`Linear.sol:25-28`](src/strategy/Linear.sol:25))
4. **Fee Validation** with MIN_FEE (100 bps = 0.01%) / MAX_FEE (100000 bps = 10%) bounds ([`GridOrder.sol:17-20`](src/libraries/GridOrder.sol:17))
5. **Safe Math** via Solidity 0.8.33 built-in overflow checks
6. **SafeTransferLib** for ERC20 transfers
7. **512-bit Math** via FullMath library for precision in price calculations
8. **Input Validation** in require statements with proper error messages

---

## Medium Findings

### [M-01] tryPaybackETH Silently Fails (Acknowledged)

**Severity:** Medium  
**Location:** [`src/AssetSettle.sol:56-59`](src/AssetSettle.sol:56)

**Description:**

The [`tryPaybackETH()`](src/AssetSettle.sol:56) function silently ignores failed ETH transfers:

```solidity
function tryPaybackETH(address to, uint256 value) internal {
    (bool success,) = to.call{value: value}(new bytes(0));
    success;  // Intentionally ignored
}
```

**Impact:**

- If a user's contract cannot receive ETH, the refund is lost
- Users may not realize they didn't receive their refund
- ETH accumulates in the contract

**Mitigating Factors:**

1. The [`rescueEth()`](src/GridEx.sol:659) function allows owner to recover stuck ETH
2. This is a known design decision for gas efficiency
3. Users can avoid this by using EOA accounts or contracts that accept ETH

**Recommendation:**

Consider implementing a pull pattern for refunds or emitting an event when refund fails:

```solidity
event RefundFailed(address indexed to, uint256 amount);

function tryPaybackETH(address to, uint256 value) internal {
    (bool success,) = to.call{value: value}("");
    if (!success) {
        emit RefundFailed(to, value);
    }
}
```

---

## Low Findings

### [L-01] Fee Split Calculation Uses Bit Shift Instead of Documented Percentage

**Severity:** Low  
**Location:** [`src/libraries/Lens.sol:124-130`](src/libraries/Lens.sol:124)

**Description:**

The fee calculation uses bit shift (`>> 2`) which results in 25% protocol fee, not 60% as documented in the previous audit:

```solidity
function calculateFees(uint128 vol, uint32 bps) public pure returns (uint128 lpFee, uint128 protocolFee) {
    unchecked {
        uint128 fee = uint128((uint256(vol) * uint256(bps)) / 1000000);
        protocolFee = fee >> 2;  // 25% to protocol (not 60%)
        lpFee = fee - protocolFee;  // 75% to LP
    }
}
```

**Impact:**

- Documentation mismatch - actual split is 75% LP / 25% protocol
- No functional issue, but could cause confusion

**Recommendation:**

Update documentation to reflect actual fee split (75% LP / 25% protocol) or add named constants:

```solidity
uint256 constant PROTOCOL_FEE_DIVISOR = 4; // 25% to protocol
```

---

### [L-02] Unchecked Arithmetic in Multiple Locations

**Severity:** Low  
**Location:** Multiple files

**Description:**

Several `unchecked` blocks are used for gas optimization:

- [`src/libraries/GridOrder.sol:574-577`](src/libraries/GridOrder.sol:574) - cancelGrid loop
- [`src/libraries/GridOrder.sol:592-595`](src/libraries/GridOrder.sol:592) - cancelGrid loop
- [`src/libraries/GridOrder.sol:644-647`](src/libraries/GridOrder.sol:644) - cancelGridOrders loop
- [`src/libraries/GridOrder.sol:397-399`](src/libraries/GridOrder.sol:397) - fillAskOrder

While these appear safe due to prior validation (amounts come from order storage), unchecked arithmetic always carries risk.

**Recommendation:**

Add comments explaining why overflow is impossible in each case:

```solidity
unchecked {
    // Safe: ba and qa are uint128 from storage, sum cannot exceed uint256
    baseAmt += ba;
    quoteAmt += qa;
}
```

---

### [L-03] Missing Event Emission for Quote Token Removal

**Severity:** Low  
**Location:** [`src/GridEx.sol:646-652`](src/GridEx.sol:646)

**Description:**

The [`setQuoteToken()`](src/GridEx.sol:646) function emits `QuotableTokenUpdated` for both adding and removing tokens (priority=0), but there's no distinction:

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

## Informational Findings

### [I-01] Commented Out Code Throughout Codebase

**Severity:** Informational  
**Location:** Multiple files

**Description:**

Commented-out code exists in several locations:
- [`src/libraries/GridOrder.sol:301-306`](src/libraries/GridOrder.sol:301) - Old price calculation
- [`src/libraries/GridOrder.sol:316-321`](src/libraries/GridOrder.sol:316) - Old price calculation
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
- Require with strings: `require(condition, "G1")`, `require(condition, "L1")`

**Recommendation:**

Standardize on custom errors for gas efficiency and clarity. Replace all `require(condition, "XX")` with custom errors.

---

### [I-03] Magic Numbers in Code

**Severity:** Informational  
**Location:** Multiple files

**Description:**

Several magic numbers without named constants:
- `1 << 20`, `1 << 19` in quotableTokens priority ([`GridEx.sol:51-53`](src/GridEx.sol:51))
- `0x80000000000000000000000000000001` for ask order ID start ([`GridOrder.sol:158`](src/libraries/GridOrder.sol:158))
- `1000000` for fee calculation divisor ([`Lens.sol:126`](src/libraries/Lens.sol:126))
- `10 ** 36` for PRICE_MULTIPLIER ([`Lens.sol:14`](src/libraries/Lens.sol:14), [`Linear.sol:14`](src/strategy/Linear.sol:14))

**Recommendation:**

Define named constants for all magic numbers:

```solidity
uint256 public constant USD_PRIORITY = 1 << 20;
uint256 public constant WETH_PRIORITY = 1 << 19;
uint256 public constant FEE_DENOMINATOR = 1000000;
```

---

### [I-04] Missing NatSpec Documentation

**Severity:** Informational  
**Location:** Multiple files

**Description:**

While most public functions have NatSpec, some internal functions and edge cases lack documentation:
- Internal helper functions in GridOrder.sol
- Some error conditions and their triggers

**Recommendation:**

Add comprehensive NatSpec documentation for all functions, including internal ones.

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

1. **Vault.sol**: No tests for withdrawal functions (`withdrawERC20`, `withdrawETH`)
2. **Linear.sol**: No direct tests for strategy validation edge cases
3. **modifyGridFee**: Function exists in GridOrder.sol but not exposed in GridEx
4. **Callback pattern**: Limited testing of callback scenarios with malicious receivers
5. **Edge cases**: 
   - Maximum order counts (uint32 max)
   - Minimum amounts near zero
   - Fee boundary conditions (MIN_FEE, MAX_FEE)
   - Pair creation with equal priority tokens
   - Failed ETH refunds

### Recommendations for Test Improvement

1. Add fuzz tests for arithmetic operations
2. Add invariant tests for token conservation
3. Test all error conditions explicitly
4. Add integration tests with real token contracts
5. Test callback pattern with malicious receivers
6. Add tests for Vault withdrawal functions
7. Test Linear strategy edge cases (negative gaps, overflow scenarios)

---

## Recommendations

### Immediate Actions (Pre-Deployment)

1. **Clean up**: Remove commented code throughout codebase
2. **Documentation**: Update fee split documentation to reflect actual 75/25 split
3. **Constants**: Add named constants for magic numbers

### Short-Term Improvements

1. Add event emission for failed ETH refunds (M-01)
2. Standardize error handling to custom errors
3. Add comprehensive test coverage for Vault and Linear contracts
4. Add NatSpec documentation for internal functions

### Long-Term Improvements

1. Add comprehensive fuzz and invariant tests
2. Consider formal verification for core math (FullMath, Lens)
3. Gas optimization pass
4. Consider upgradeability pattern for future improvements
5. Consider implementing pull pattern for ETH refunds

---

## Security Checklist

| Check | Status |
|-------|--------|
| Reentrancy protection | ✅ ReentrancyGuard on all fill functions |
| Integer overflow/underflow | ✅ Solidity 0.8.33 built-in checks |
| Access control | ✅ Owned pattern, onlyGridEx modifier |
| Input validation | ✅ Comprehensive validation |
| External calls at end | ⚠️ Callback pattern transfers first (mitigated by balance check) |
| Check return values | ✅ SafeTransferLib used |
| No tx.origin | ✅ Not used |
| Event emission | ✅ Events for all state changes |
| Emergency stop | ❌ No pause mechanism |
| Upgrade mechanism | ❌ Not upgradeable |
| Fee bounds validation | ✅ MIN_FEE/MAX_FEE enforced |
| Strategy access control | ✅ onlyGridEx modifier |

---

## Conclusion

The GridEx protocol demonstrates mature security practices and has addressed all critical and high-severity issues from previous audits. The codebase is well-structured with:

- Proper access control via Owned pattern and onlyGridEx modifier
- ReentrancyGuard protection on all fill functions
- Comprehensive input validation with fee bounds
- Safe math operations via Solidity 0.8.33 and FullMath library
- SafeTransferLib for ERC20 transfers

The remaining findings are primarily low severity and informational:
- Silent ETH refund failures (M-01) - mitigated by rescueEth function
- Documentation/code consistency issues
- Test coverage gaps

The protocol is suitable for production deployment with the recommended improvements. The permissionless pair creation is an intentional design decision for a decentralized exchange.

---

## Appendix: Contract Interaction Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Maker     │     │   GridEx    │     │   Taker     │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       │ placeGridOrders() │                   │
       │──────────────────>│                   │
       │                   │                   │
       │                   │ fillAskOrder()    │
       │                   │<──────────────────│
       │                   │                   │
       │                   │ (callback if data)│
       │                   │──────────────────>│
       │                   │                   │
       │                   │ balance check     │
       │                   │<──────────────────│
       │                   │                   │
       │ withdrawProfits() │                   │
       │──────────────────>│                   │
       │                   │                   │
       │ cancelGrid()      │                   │
       │──────────────────>│                   │
       │                   │                   │
```

---

## Disclaimer

This audit report is not a guarantee of security. Smart contract security is a continuous process, and new vulnerabilities may be discovered after this audit. The findings in this report are based on the code reviewed at the time of the audit and may not reflect subsequent changes.

---

**End of Report**
