// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Lens} from "../src/libraries/Lens.sol";
import {FullMath} from "../src/libraries/FullMath.sol";
import {GridOrder} from "../src/libraries/GridOrder.sol";

/// @title GridExFuzzTest
/// @notice Fuzz tests for arithmetic operations in Lens and FullMath libraries
contract GridExFuzzTest is Test {
    uint256 constant PRICE_MULTIPLIER = 10 ** 36;
    uint32 constant MIN_FEE = 100;
    uint32 constant MAX_FEE = 100000;

    // ============ Lens.calcQuoteAmount Fuzz Tests ============

    /// @notice Fuzz test calcQuoteAmount with valid inputs
    function testFuzz_calcQuoteAmount_valid(uint128 baseAmt, uint256 price) public pure {
        // Bound inputs to valid ranges
        vm.assume(baseAmt > 0);
        vm.assume(price > 0 && price < type(uint128).max);
        
        // Calculate expected result
        uint256 expected = FullMath.mulDiv(uint256(baseAmt), price, PRICE_MULTIPLIER);
        
        // Skip if result would be zero or overflow
        vm.assume(expected > 0 && expected < type(uint128).max);
        
        uint128 result = Lens.calcQuoteAmount(baseAmt, price, false);
        assertEq(result, expected);
    }

    /// @notice Fuzz test calcQuoteAmount rounding up
    function testFuzz_calcQuoteAmount_roundUp(uint128 baseAmt, uint256 price) public pure {
        // Need meaningful amounts to avoid zero results
        vm.assume(baseAmt > 1e15);
        vm.assume(price > PRICE_MULTIPLIER / 1000 && price < type(uint128).max);
        
        uint256 expectedRoundDown = FullMath.mulDiv(uint256(baseAmt), price, PRICE_MULTIPLIER);
        uint256 expectedRoundUp = FullMath.mulDivRoundingUp(uint256(baseAmt), price, PRICE_MULTIPLIER);
        
        vm.assume(expectedRoundUp > 0 && expectedRoundUp < type(uint128).max);
        vm.assume(expectedRoundDown > 0);
        
        uint128 resultDown = Lens.calcQuoteAmount(baseAmt, price, false);
        uint128 resultUp = Lens.calcQuoteAmount(baseAmt, price, true);
        
        // Round up should be >= round down
        assertTrue(resultUp >= resultDown);
        
        // Difference should be at most 1
        assertTrue(resultUp - resultDown <= 1);
    }

    /// @notice Fuzz test calcQuoteAmount reverts on zero result
    function testFuzz_calcQuoteAmount_revertsOnZero(uint128 baseAmt, uint256 price) public {
        vm.assume(baseAmt > 0 && baseAmt < 1e20);
        vm.assume(price > 0 && price < PRICE_MULTIPLIER / 1e20);
        
        uint256 expected = FullMath.mulDiv(uint256(baseAmt), price, PRICE_MULTIPLIER);
        
        if (expected == 0) {
            vm.expectRevert();
            Lens.calcQuoteAmount(baseAmt, price, false);
        }
    }

    // ============ Lens.calcBaseAmount Fuzz Tests ============

    /// @notice Fuzz test calcBaseAmount with valid inputs
    function testFuzz_calcBaseAmount_valid(uint128 quoteAmt, uint256 price) public pure {
        vm.assume(quoteAmt > 0);
        vm.assume(price > 0 && price < type(uint128).max);
        
        uint256 expected = FullMath.mulDiv(uint256(quoteAmt), PRICE_MULTIPLIER, price);
        
        vm.assume(expected > 0 && expected < type(uint128).max);
        
        uint256 result = Lens.calcBaseAmount(quoteAmt, price, false);
        assertEq(result, expected);
    }

    /// @notice Fuzz test calcBaseAmount rounding
    function testFuzz_calcBaseAmount_roundUp(uint128 quoteAmt, uint256 price) public pure {
        // Need meaningful amounts to avoid zero results
        vm.assume(quoteAmt > 1e15);
        vm.assume(price > PRICE_MULTIPLIER / 1e20 && price < PRICE_MULTIPLIER * 1e10);
        
        uint256 expectedRoundDown = FullMath.mulDiv(uint256(quoteAmt), PRICE_MULTIPLIER, price);
        uint256 expectedRoundUp = FullMath.mulDivRoundingUp(uint256(quoteAmt), PRICE_MULTIPLIER, price);
        
        vm.assume(expectedRoundUp > 0 && expectedRoundUp < type(uint128).max);
        vm.assume(expectedRoundDown > 0);
        
        uint256 resultDown = Lens.calcBaseAmount(quoteAmt, price, false);
        uint256 resultUp = Lens.calcBaseAmount(quoteAmt, price, true);
        
        assertTrue(resultUp >= resultDown);
        assertTrue(resultUp - resultDown <= 1);
    }

    // ============ Lens.calcAskOrderQuoteAmount Fuzz Tests ============

    /// @notice Fuzz test calcAskOrderQuoteAmount
    function testFuzz_calcAskOrderQuoteAmount(uint128 baseAmt, uint256 price, uint32 feebps) public pure {
        vm.assume(baseAmt > 0);
        vm.assume(price > 0 && price < type(uint128).max);
        vm.assume(feebps >= MIN_FEE && feebps <= MAX_FEE);
        
        uint256 quoteVol = FullMath.mulDivRoundingUp(uint256(baseAmt), price, PRICE_MULTIPLIER);
        vm.assume(quoteVol > 0 && quoteVol < type(uint128).max);
        
        (uint128 resultVol, uint128 resultFee) = Lens.calcAskOrderQuoteAmount(price, baseAmt, feebps);
        
        // Verify quote volume
        assertEq(resultVol, quoteVol);
        
        // Verify fee calculation
        uint128 expectedFee = uint128((uint256(resultVol) * uint256(feebps)) / 1000000);
        assertEq(resultFee, expectedFee);
        
        // Fee should be less than volume
        assertTrue(resultFee <= resultVol);
    }

    /// @notice Fuzz test calcBidOrderQuoteAmount
    function testFuzz_calcBidOrderQuoteAmount(uint128 baseAmt, uint256 price, uint32 feebps) public pure {
        vm.assume(baseAmt > 0);
        vm.assume(price > 0 && price < type(uint128).max);
        vm.assume(feebps >= MIN_FEE && feebps <= MAX_FEE);
        
        uint256 filledVol = FullMath.mulDiv(uint256(baseAmt), price, PRICE_MULTIPLIER);
        vm.assume(filledVol > 0 && filledVol < type(uint128).max);
        
        (uint128 resultVol, uint128 resultFee) = Lens.calcBidOrderQuoteAmount(price, baseAmt, feebps);
        
        // Verify filled volume
        assertEq(resultVol, filledVol);
        
        // Verify fee calculation
        uint128 expectedFee = uint128((uint256(resultVol) * uint256(feebps)) / 1000000);
        assertEq(resultFee, expectedFee);
        
        // Fee should be less than volume
        assertTrue(resultFee <= resultVol);
    }

    // ============ Lens.calculateFees Fuzz Tests ============

    /// @notice Fuzz test calculateFees
    function testFuzz_calculateFees(uint128 vol, uint32 bps) public pure {
        vm.assume(vol > 0);
        vm.assume(bps >= MIN_FEE && bps <= MAX_FEE);
        
        (uint128 lpFee, uint128 protocolFee) = Lens.calculateFees(vol, bps);
        
        // Total fee
        uint128 totalFee = uint128((uint256(vol) * uint256(bps)) / 1000000);
        
        // Protocol fee should be 25% (fee >> 2)
        assertEq(protocolFee, totalFee >> 2);
        
        // LP fee should be 75%
        assertEq(lpFee, totalFee - protocolFee);
        
        // Sum should equal total
        assertEq(lpFee + protocolFee, totalFee);
    }

    /// @notice Fuzz test fee split ratio
    function testFuzz_feeSplitRatio(uint128 vol, uint32 bps) public pure {
        vm.assume(vol > 100); // Need enough volume for meaningful fee
        vm.assume(bps >= MIN_FEE && bps <= MAX_FEE);
        
        (uint128 lpFee, uint128 protocolFee) = Lens.calculateFees(vol, bps);
        
        // Protocol fee should be approximately 25% of total
        // Due to integer division, we check within 1 unit
        uint128 totalFee = lpFee + protocolFee;
        if (totalFee >= 4) {
            assertTrue(protocolFee <= (totalFee / 4) + 1);
            assertTrue(protocolFee >= (totalFee / 4) - 1 || totalFee / 4 == 0);
        }
    }

    // ============ FullMath Fuzz Tests ============

    /// @notice Fuzz test FullMath.mulDiv
    function testFuzz_fullMath_mulDiv(uint256 a, uint256 b, uint256 denominator) public pure {
        vm.assume(denominator > 0);
        vm.assume(a > 0 && b > 0);
        
        // Avoid overflow: a * b / denominator should fit in uint256
        // If a * b would overflow, skip
        if (a > type(uint256).max / b) {
            return;
        }
        
        uint256 result = FullMath.mulDiv(a, b, denominator);
        
        // Verify result is correct (within rounding)
        // result * denominator <= a * b < (result + 1) * denominator
        assertTrue(result <= (a * b) / denominator);
    }

    /// @notice Fuzz test FullMath.mulDivRoundingUp
    function testFuzz_fullMath_mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) public pure {
        vm.assume(denominator > 0);
        vm.assume(a > 0 && b > 0);
        
        if (a > type(uint256).max / b) {
            return;
        }
        
        uint256 resultDown = FullMath.mulDiv(a, b, denominator);
        uint256 resultUp = FullMath.mulDivRoundingUp(a, b, denominator);
        
        // Round up should be >= round down
        assertTrue(resultUp >= resultDown);
        
        // Difference should be at most 1
        assertTrue(resultUp - resultDown <= 1);
    }

    // ============ Price Calculation Consistency Tests ============

    /// @notice Fuzz test that quote -> base -> quote is consistent
    function testFuzz_priceConsistency_quoteBaseQuote(uint128 baseAmt, uint256 price) public pure {
        // Use bound() instead of vm.assume() to avoid rejecting too many inputs
        baseAmt = uint128(bound(uint256(baseAmt), 1e18, type(uint128).max));
        price = bound(price, PRICE_MULTIPLIER / 100, PRICE_MULTIPLIER * 100);
        
        // Calculate quote from base
        uint256 quoteVol = FullMath.mulDiv(uint256(baseAmt), price, PRICE_MULTIPLIER);
        
        // Skip if quote would be zero or overflow
        if (quoteVol == 0 || quoteVol >= type(uint128).max) {
            return;
        }
        
        // Calculate base from quote
        uint256 baseBack = FullMath.mulDiv(quoteVol, PRICE_MULTIPLIER, price);
        
        // Should be close to original (within rounding)
        // Due to integer division, we may lose precision
        // The difference should be small relative to the amount
        assertTrue(baseBack <= baseAmt);
        // Allow up to 1e-15 relative error or 1 absolute error
        uint256 diff = baseAmt - baseBack;
        assertTrue(diff <= baseAmt / 1e15 + 1);
    }

    /// @notice Fuzz test fee calculation doesn't overflow
    function testFuzz_feeNoOverflow(uint128 vol, uint32 bps) public pure {
        vm.assume(bps <= MAX_FEE);
        
        // This should never overflow
        uint256 fee = (uint256(vol) * uint256(bps)) / 1000000;
        
        // Fee should always be less than volume
        assertTrue(fee <= vol);
        
        // Fee should fit in uint128
        assertTrue(fee < type(uint128).max);
    }

    // ============ Grid Order ID Fuzz Tests ============

    /// @notice Fuzz test grid order ID encoding/decoding
    function testFuzz_gridOrderId_roundtrip(uint128 gridId, uint128 orderId) public pure {
        uint256 combined = GridOrder.toGridOrderId(gridId, orderId);
        
        (uint128 extractedGridId, uint128 extractedOrderId) = GridOrder.extractGridIdOrderId(combined);
        
        assertEq(extractedGridId, gridId);
        assertEq(extractedOrderId, orderId);
    }

    /// @notice Fuzz test ask order identification
    function testFuzz_isAskGridOrder(uint128 orderId) public pure {
        // Ask orders have high bit set (>= 0x80000000000000000000000000000000)
        bool isAsk = GridOrder.isAskGridOrder(orderId);
        
        if (orderId >= 0x80000000000000000000000000000000) {
            assertTrue(isAsk);
        } else {
            assertFalse(isAsk);
        }
    }

    // ============ Boundary Condition Fuzz Tests ============

    /// @notice Fuzz test near-boundary prices
    function testFuzz_nearBoundaryPrice(uint128 baseAmt) public pure {
        vm.assume(baseAmt > 0 && baseAmt < 1e30);
        
        // Test with very small price
        uint256 smallPrice = 1;
        uint256 smallResult = FullMath.mulDiv(uint256(baseAmt), smallPrice, PRICE_MULTIPLIER);
        // Result should be 0 or very small
        assertTrue(smallResult < baseAmt);
        
        // Test with price = PRICE_MULTIPLIER (1:1)
        uint256 oneToOneResult = FullMath.mulDiv(uint256(baseAmt), PRICE_MULTIPLIER, PRICE_MULTIPLIER);
        assertEq(oneToOneResult, baseAmt);
    }

    /// @notice Fuzz test fee boundaries
    function testFuzz_feeBoundaries(uint128 vol) public pure {
        vm.assume(vol > 0);
        
        // Test with MIN_FEE
        (uint128 lpFeeMin, uint128 protocolFeeMin) = Lens.calculateFees(vol, MIN_FEE);
        uint128 totalFeeMin = lpFeeMin + protocolFeeMin;
        
        // Test with MAX_FEE
        (uint128 lpFeeMax, uint128 protocolFeeMax) = Lens.calculateFees(vol, MAX_FEE);
        uint128 totalFeeMax = lpFeeMax + protocolFeeMax;
        
        // Max fee should be >= min fee
        assertTrue(totalFeeMax >= totalFeeMin);
        
        // Both should be <= volume
        assertTrue(totalFeeMin <= vol);
        assertTrue(totalFeeMax <= vol);
    }

    // ============ Arithmetic Property Tests ============

    /// @notice Fuzz test commutativity of multiplication in mulDiv
    function testFuzz_mulDiv_commutativity(uint256 a, uint256 b, uint256 denom) public pure {
        vm.assume(denom > 0);
        vm.assume(a > 0 && b > 0);
        vm.assume(a < type(uint128).max && b < type(uint128).max);
        
        uint256 result1 = FullMath.mulDiv(a, b, denom);
        uint256 result2 = FullMath.mulDiv(b, a, denom);
        
        assertEq(result1, result2);
    }

    /// @notice Fuzz test that larger base amounts produce larger quote amounts
    function testFuzz_monotonicity_baseToQuote(uint128 baseAmt1, uint128 baseAmt2, uint256 price) public pure {
        vm.assume(baseAmt1 > 0 && baseAmt2 > 0);
        vm.assume(baseAmt1 != baseAmt2);
        vm.assume(price > 0 && price < type(uint128).max);
        
        uint256 quote1 = FullMath.mulDiv(uint256(baseAmt1), price, PRICE_MULTIPLIER);
        uint256 quote2 = FullMath.mulDiv(uint256(baseAmt2), price, PRICE_MULTIPLIER);
        
        if (baseAmt1 > baseAmt2) {
            assertTrue(quote1 >= quote2);
        } else {
            assertTrue(quote2 >= quote1);
        }
    }

    /// @notice Fuzz test that higher fees produce higher fee amounts
    function testFuzz_monotonicity_fees(uint128 vol, uint32 fee1, uint32 fee2) public pure {
        vm.assume(vol > 0);
        vm.assume(fee1 >= MIN_FEE && fee1 <= MAX_FEE);
        vm.assume(fee2 >= MIN_FEE && fee2 <= MAX_FEE);
        vm.assume(fee1 != fee2);
        
        (uint128 lpFee1, uint128 protocolFee1) = Lens.calculateFees(vol, fee1);
        (uint128 lpFee2, uint128 protocolFee2) = Lens.calculateFees(vol, fee2);
        
        uint128 total1 = lpFee1 + protocolFee1;
        uint128 total2 = lpFee2 + protocolFee2;
        
        if (fee1 > fee2) {
            assertTrue(total1 >= total2);
        } else {
            assertTrue(total2 >= total1);
        }
    }
}
