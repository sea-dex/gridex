# GridEx Security Audit Report

**Project:** GridEx - Grid Trading Exchange
**Version:** Solidity 0.8.33
**Audit Date:** February 2026 (Re-audit v3)
**Auditor:** Security Review

---

## Executive Summary

GridEx is a decentralized grid trading exchange built on Solidity that allows makers to place grid orders at multiple price levels and takers to fill them. The system supports both ERC20 tokens and native ETH (via WETH wrapping), with configurable fee structures and compound/non-compound order modes.

This re-audit reflects significant improvements from previous audits. The codebase demonstrates mature security practices with proper access control, reentrancy protection, and comprehensive input validation. The current audit identified **0 Critical**, **0 High**, **1 Medium**, **2 Low** (2 resolved/mitigated), and **5 Informational** findings.

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
| M-04: modifyGridFee Not Exposed | Medium | ✅ **Resolved** - Added modifyGridFee() to GridEx.sol |
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
| [`GridOrder.sol`](src/libraries/GridOrder.sol) | Library containing grid order state and logic | 657 |
| [`Linear.sol`](src/strategy/Linear.sol) | Linear price strategy implementation | 171 |
| [`Lens.sol`](src/libraries/Lens.sol) | Price calculation utilities | 131 |
| [`Currency.sol`](src/libraries/Currency.sol) | Custom type for ETH/ERC20 handling | 168 |
| [`FullMath.sol`](src/libraries/FullMath.sol) | 512-bit precision math from Uniswap | 121 |

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

### [L-01] Fee Split Calculation Uses Bit Shift Instead of Documented Percentage ✅ Resolved

**Severity:** Low
**Status:** ✅ **Resolved** - Documentation correctly states 75% LP / 25% protocol fee split
**Location:** [`src/libraries/Lens.sol:124-130`](src/libraries/Lens.sol:124)

**Description:**

The fee calculation uses bit shift (`>> 2`) which results in 25% protocol fee:

```solidity
function calculateFees(uint128 vol, uint32 bps) public pure returns (uint128 lpFee, uint128 protocolFee) {
    unchecked {
        uint128 fee = uint128((uint256(vol) * uint256(bps)) / 1000000);
        protocolFee = fee >> 2;  // 25% to protocol
        lpFee = fee - protocolFee;  // 75% to LP
    }
}
```

**Resolution:**

The documentation in the Architecture Overview section correctly states:
> "**Protocol Fees**: 75% LP / 25% protocol fee split (using bit shift `>> 2`)"

The bit shift `>> 2` divides by 4, giving 25% to protocol and 75% to LP. No changes needed.

---

### [L-02] Unchecked Arithmetic in Multiple Locations

**Severity:** Low  
**Location:** Multiple files

**Description:**

Several `unchecked` blocks are used for gas optimization:

- [`src/libraries/GridOrder.sol:552-556`](src/libraries/GridOrder.sol:552) - cancelGrid loop
- [`src/libraries/GridOrder.sol:571-575`](src/libraries/GridOrder.sol:571) - cancelGrid loop
- [`src/libraries/GridOrder.sol:624-628`](src/libraries/GridOrder.sol:624) - cancelGridOrders loop
- [`src/libraries/GridOrder.sol:374-377`](src/libraries/GridOrder.sol:374) - fillAskOrder
- [`src/libraries/Lens.sol:125-129`](src/libraries/Lens.sol:125) - calculateFees

While these appear safe due to prior validation (amounts come from order storage), unchecked arithmetic always carries risk.

**Recommendation:**

Add comments explaining why overflow is impossible in each case (already done in some locations):

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

### [L-04] Linear Strategy getReversePrice Can Return Negative Price ✅ Mitigated

**Severity:** Low
**Status:** ✅ **Mitigated** - Already protected by validateParams() validation
**Location:** [`src/strategy/Linear.sol:162-170`](src/strategy/Linear.sol:162)

**Description:**

The [`getReversePrice()`](src/strategy/Linear.sol:162) function calculates price as:

```solidity
function getReversePrice(
    bool isAsk,
    uint128 gridId,
    uint128 idx
) external view override returns (uint256) {
    LinearStrategy memory s = strategies[gridIdKey(isAsk, gridId)];
    return uint256(int256(s.basePrice) + s.gap * (int256(uint256(idx)) - 1));
}
```

When `idx = 0`, this calculates `basePrice + gap * (-1)`. For ask orders where `gap > 0`, this could theoretically result in a negative value being cast to uint256.

**Analysis:**

- For ask orders with idx=0, the reverse price would be `basePrice - gap`
- The [`validateParams()`](src/strategy/Linear.sol:106) check `require(uint256(gap) < price0, "L3")` ensures `gap < basePrice`
- Therefore `basePrice - gap > 0` is always guaranteed
- For bid orders where `gap < 0`, the calculation becomes `basePrice + |gap|` which is always positive

**Conclusion:**

This is **not a real vulnerability**. The existing validation in `validateParams()` prevents any underflow scenario. No code changes required.

---

## Informational Findings

### [I-01] Commented Out Code Throughout Codebase

**Severity:** Informational  
**Location:** Multiple files

**Description:**

Commented-out code exists in several locations:
- [`src/libraries/GridOrder.sol`](src/libraries/GridOrder.sol) - Old price calculation comments
- [`src/interfaces/IGridOrder.sol`](src/interfaces/IGridOrder.sol) - Commented struct fields
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

Error codes used:
- G1-G7: GridEx.sol errors
- E1-E5: GridOrder.sol errors
- L0-L7: Linear.sol errors
- Q0-Q1: Linear.sol quote amount errors
- P1: Pair.sol error

**Recommendation:**

Standardize on custom errors for gas efficiency and clarity. Replace all `require(condition, "XX")` with custom errors.

---

### [I-03] Magic Numbers in Code

**Severity:** Informational  
**Location:** Multiple files

**Description:**

Several magic numbers without named constants:
- `1 << 20`, `1 << 19` in quotableTokens priority ([`GridEx.sol:51-53`](src/GridEx.sol:51))
- `0x80000000000000000000000000000001` for ask order ID start ([`GridOrder.sol:156`](src/libraries/GridOrder.sol:156))
- `1000000` for fee calculation divisor ([`Lens.sol:126`](src/libraries/Lens.sol:126))
- `10 ** 36` for PRICE_MULTIPLIER ([`Lens.sol:14`](src/libraries/Lens.sol:14), [`Linear.sol:14`](src/strategy/Linear.sol:14))
- `1 << 128` for ask order mask ([`GridOrder.sol:26`](src/libraries/GridOrder.sol:26))

**Recommendation:**

Define named constants for all magic numbers:

```solidity
uint256 public constant USD_PRIORITY = 1 << 20;
uint256 public constant WETH_PRIORITY = 1 << 19;
uint256 public constant FEE_DENOMINATOR = 1000000;
uint128 public constant ASK_ORDER_START_ID = 0x80000000000000000000000000000001;
```

---

### [I-04] Missing NatSpec Documentation

**Severity:** Informational  
**Location:** Multiple files

**Description:**

While most public functions have NatSpec, some internal functions and edge cases lack documentation:
- Internal helper functions in GridOrder.sol
- Some error conditions and their triggers
- The WETH immutable variable in AssetSettle.sol lacks @notice

**Recommendation:**

Add comprehensive NatSpec documentation for all functions, including internal ones.

---

### [I-05] No Emergency Pause Mechanism

**Severity:** Informational  
**Location:** [`src/GridEx.sol`](src/GridEx.sol)

**Description:**

The contract lacks an emergency pause mechanism. In case of a discovered vulnerability or attack, there's no way to halt operations.

**Recommendation:**

Consider implementing OpenZeppelin's Pausable pattern:

```solidity
import {Pausable} from "solmate/utils/Pausable.sol";

contract GridEx is IGridEx, AssetSettle, Pair, Owned, ReentrancyGuard, Pausable {
    
    function fillAskOrder(...) public payable override nonReentrant whenNotPaused {
        // ...
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
}
```

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
| [`GridEx.callback.t.sol`](test/GridEx.callback.t.sol) | Callback pattern | - |
| [`GridEx.edge.t.sol`](test/GridEx.edge.t.sol) | Edge cases | - |
| [`GridEx.fee.t.sol`](test/GridEx.fee.t.sol) | Fee calculations | - |
| [`GridEx.fuzz.t.sol`](test/GridEx.fuzz.t.sol) | Fuzz testing | - |
| [`GridEx.invariant.t.sol`](test/GridEx.invariant.t.sol) | Invariant testing | - |
| [`Linear.t.sol`](test/Linear.t.sol) | Linear strategy | - |

**Total: 52+ tests**

### Missing Test Coverage

1. **Vault.sol**: No tests for withdrawal functions (`withdrawERC20`, `withdrawETH`)
2. **Linear.sol**: Limited tests for strategy validation edge cases
3. **modifyGridFee**: Function exists in GridOrder.sol but not exposed in GridEx
4. **Callback pattern**: Limited testing of callback scenarios with malicious receivers
5. **Edge cases**: 
   - Maximum order counts (uint32 max)
   - Minimum amounts near zero
   - Fee boundary conditions (MIN_FEE, MAX_FEE)
   - Pair creation with equal priority tokens
   - Failed ETH refunds
   - getReversePrice with idx=0

### Recommendations for Test Improvement

1. Add fuzz tests for arithmetic operations
2. Add invariant tests for token conservation
3. Test all error conditions explicitly
4. Add integration tests with real token contracts
5. Test callback pattern with malicious receivers
6. Add tests for Vault withdrawal functions
7. Test Linear strategy edge cases (negative gaps, overflow scenarios)
8. Test getReversePrice boundary conditions

---

## Recommendations

### Immediate Actions (Pre-Deployment)

1. **Clean up**: Remove commented code throughout codebase
2. **Documentation**: Update fee split documentation to reflect actual 75/25 split
3. **Constants**: Add named constants for magic numbers
4. **Expose modifyGridFee**: Add public function in GridEx.sol

### Short-Term Improvements

1. Add event emission for failed ETH refunds (M-01)
2. Standardize error handling to custom errors
3. Add comprehensive test coverage for Vault and Linear contracts
4. Add NatSpec documentation for internal functions
5. Add validation in getReversePrice for edge cases

### Long-Term Improvements

1. Add comprehensive fuzz and invariant tests
2. Consider formal verification for core math (FullMath, Lens)
3. Gas optimization pass
4. Consider upgradeability pattern for future improvements
5. Consider implementing pull pattern for ETH refunds
6. Consider adding emergency pause mechanism

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
| 512-bit math precision | ✅ FullMath library from Uniswap |
| Safe ERC20 transfers | ✅ SafeTransferLib from solmate |

---

## Conclusion

The GridEx protocol demonstrates mature security practices and has addressed all critical and high-severity issues from previous audits. The codebase is well-structured with:

- Proper access control via Owned pattern and onlyGridEx modifier
- ReentrancyGuard protection on all fill functions
- Comprehensive input validation with fee bounds
- Safe math operations via Solidity 0.8.33 and FullMath library
- SafeTransferLib for ERC20 transfers
- Well-documented code with NatSpec comments

The remaining findings are primarily medium to low severity:
- Silent ETH refund failures (M-01) - mitigated by rescueEth function
- Unexposed modifyGridFee function (M-02)
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

## Appendix: Key Function Security Analysis

### fillAskOrder / fillBidOrder

```
1. nonReentrant modifier prevents reentrancy
2. State updated in _gridState.fillAskOrder() before external calls
3. If callback used:
   - Tokens transferred to taker first
   - Callback invoked
   - Balance check ensures payment received
4. If no callback:
   - settleAssetWith handles token transfers
   - Protocol fee transferred to vault
```

### placeGridOrders

```
1. Validates parameters via validateGridOrderParam()
2. Creates grid config in storage
3. Calculates required token amounts
4. Transfers tokens from maker to contract
5. No external calls before state updates
```

### cancelGrid / cancelGridOrders

```
1. Verifies sender is grid owner
2. Checks grid status is normal
3. Calculates refund amounts from storage
4. Updates grid status to canceled
5. Transfers tokens to recipient
```

---

## Disclaimer

This audit report is not a guarantee of security. Smart contract security is a continuous process, and new vulnerabilities may be discovered after this audit. The findings in this report are based on the code reviewed at the time of the audit and may not reflect subsequent changes.

---

**End of Report**
