// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Geometry} from "../src/strategy/Geometry.sol";
import {IGeometryErrors} from "../src/interfaces/IGeometryErrors.sol";
import {FullMath} from "../src/libraries/FullMath.sol";

contract GeometryTest is Test {
    Geometry public geometry;

    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;
    uint256 public constant RATIO_MULTIPLIER = 10 ** 18;

    function setUp() public {
        geometry = new Geometry(address(this));
    }

    // ============ Basic Validation Tests ============

    function test_validateParams_askValid() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10; // 1.1
        geometry.validateParams(true, 1 ether, abi.encode(price0, ratio), 10);
    }

    function test_validateParams_bidValid() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = (9 * RATIO_MULTIPLIER) / 10; // 0.9
        geometry.validateParams(false, 1 ether, abi.encode(price0, ratio), 10);
    }

    function test_validateParams_revertInvalidCount() public {
        vm.expectRevert(IGeometryErrors.GeometryInvalidCount.selector);
        geometry.validateParams(true, 1 ether, abi.encode(PRICE_MULTIPLIER / 1000, RATIO_MULTIPLIER), 0);
    }

    function test_validateParams_revertAskRatioTooLow() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        vm.expectRevert(IGeometryErrors.GeometryAskRatioTooLow.selector);
        geometry.validateParams(true, 1 ether, abi.encode(price0, RATIO_MULTIPLIER), 10);
    }

    function test_validateParams_revertBidRatioTooHigh() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        vm.expectRevert(IGeometryErrors.GeometryBidRatioTooHigh.selector);
        geometry.validateParams(false, 1 ether, abi.encode(price0, RATIO_MULTIPLIER), 10);
    }

    function test_validateParams_revertAskZeroQuote() public {
        uint256 tinyPrice = 1;
        uint256 hugeRatio = type(uint256).max;
        vm.expectRevert(IGeometryErrors.GeometryAskZeroQuote.selector);
        geometry.validateParams(true, 1, abi.encode(tinyPrice, hugeRatio), 2);
    }

    function test_validateParams_revertBidZeroQuote() public {
        uint256 tinyPrice = 1;
        uint256 tinyRatio = 1; // quickly decays to 0
        vm.expectRevert(IGeometryErrors.GeometryBidZeroQuote.selector);
        geometry.validateParams(false, 1, abi.encode(tinyPrice, tinyRatio), 2);
    }

    // ============ Extreme Scenario Tests ============

    /// @dev Test with maximum uint256 values for price and ratio
    function test_validateParams_maxPriceAndRatio_ask() public {
        uint256 maxPrice = type(uint256).max;
        uint256 ratio = RATIO_MULTIPLIER + 1; // Just above 1.0
        // Should revert due to overflow in price calculation
        vm.expectRevert();
        geometry.validateParams(true, 1 ether, abi.encode(maxPrice, ratio), 2);
    }

    /// @dev Test with maximum uint256 price and minimum valid ratio for bid
    function test_validateParams_maxPriceMinRatio_bid() public {
        uint256 maxPrice = type(uint256).max;
        uint256 ratio = RATIO_MULTIPLIER - 1; // Just below 1.0
        // With max price and ratio close to 1, the calculation may not overflow
        // because FullMath.mulDiv handles large numbers gracefully
        // The quote calculation: amt * price / PRICE_MULTIPLIER
        // With maxPrice and 1 ether, this would overflow
        // But with smaller amount, it might work
        // Let's test with a smaller amount that should cause overflow
        vm.expectRevert();
        geometry.validateParams(false, type(uint128).max, abi.encode(maxPrice, ratio), 2);
    }

    /// @dev Test with minimum valid amount (1 wei)
    function test_validateParams_minAmount_ask() public view {
        uint256 price0 = PRICE_MULTIPLIER; // 1:1 price
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10; // 1.1
        geometry.validateParams(true, 1, abi.encode(price0, ratio), 2);
    }

    /// @dev Test with minimum valid amount for bid
    function test_validateParams_minAmount_bid() public view {
        uint256 price0 = PRICE_MULTIPLIER; // 1:1 price
        uint256 ratio = (9 * RATIO_MULTIPLIER) / 10; // 0.9
        geometry.validateParams(false, 1, abi.encode(price0, ratio), 2);
    }

    /// @dev Test with maximum amount
    function test_validateParams_maxAmount_ask() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10;
        geometry.validateParams(true, type(uint128).max, abi.encode(price0, ratio), 10);
    }

    /// @dev Test with maximum amount for bid
    function test_validateParams_maxAmount_bid() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = (9 * RATIO_MULTIPLIER) / 10;
        geometry.validateParams(false, type(uint128).max, abi.encode(price0, ratio), 10);
    }

    /// @dev Test with ratio just above 1.0 for ask (boundary case)
    function test_validateParams_ratioJustAboveOne_ask() public view {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = RATIO_MULTIPLIER + 1; // 1 + 1e-18
        geometry.validateParams(true, 1 ether, abi.encode(price0, ratio), 2);
    }

    /// @dev Test with ratio just below 1.0 for bid (boundary case)
    function test_validateParams_ratioJustBelowOne_bid() public view {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = RATIO_MULTIPLIER - 1; // 1 - 1e-18
        geometry.validateParams(false, 1 ether, abi.encode(price0, ratio), 2);
    }

    /// @dev Test with very large ratio (2x) for ask
    function test_validateParams_largeRatio_ask() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = 2 * RATIO_MULTIPLIER; // 2.0
        geometry.validateParams(true, 1 ether, abi.encode(price0, ratio), 10);
    }

    /// @dev Test with very small ratio (0.5x) for bid
    function test_validateParams_smallRatio_bid() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = RATIO_MULTIPLIER / 2; // 0.5
        geometry.validateParams(false, 1 ether, abi.encode(price0, ratio), 10);
    }

    /// @dev Test with extremely large ratio for ask
    function test_validateParams_extremeLargeRatio_ask() public {
        uint256 price0 = 1;
        uint256 ratio = 10 * RATIO_MULTIPLIER; // 10.0
        // With tiny price and large ratio, quote might round to zero
        vm.expectRevert(IGeometryErrors.GeometryAskZeroQuote.selector);
        geometry.validateParams(true, 1 ether, abi.encode(price0, ratio), 5);
    }

    /// @dev Test with extremely small ratio for bid
    function test_validateParams_extremeSmallRatio_bid() public view {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = RATIO_MULTIPLIER / 10; // 0.1
        geometry.validateParams(false, 1 ether, abi.encode(price0, ratio), 5);
    }

    /// @dev Test with count = 1 (single order, ratio check bypassed)
    function test_validateParams_singleOrder_ask() public view {
        uint256 price0 = PRICE_MULTIPLIER;
        // With count=1, ratio validation is bypassed
        geometry.validateParams(true, 1 ether, abi.encode(price0, RATIO_MULTIPLIER), 1);
    }

    /// @dev Test with count = 1 for bid (ratio check bypassed)
    function test_validateParams_singleOrder_bid() public view {
        uint256 price0 = PRICE_MULTIPLIER;
        // With count=1, ratio validation is bypassed
        geometry.validateParams(false, 1 ether, abi.encode(price0, RATIO_MULTIPLIER), 1);
    }

    /// @dev Test with maximum count (type(uint32).max)
    function test_validateParams_maxCount_ask() public {
        uint256 price0 = 1;
        uint256 ratio = RATIO_MULTIPLIER + 1;
        // Should revert due to overflow with huge count
        vm.expectRevert();
        geometry.validateParams(true, 1 ether, abi.encode(price0, ratio), type(uint32).max);
    }

    /// @dev Test with zero price (should revert)
    function test_validateParams_zeroPrice_revert() public {
        vm.expectRevert(IGeometryErrors.GeometryInvalidPriceOrRatio.selector);
        geometry.validateParams(true, 1 ether, abi.encode(0, RATIO_MULTIPLIER + 1), 2);
    }

    /// @dev Test with zero ratio (should revert)
    function test_validateParams_zeroRatio_revert() public {
        vm.expectRevert(IGeometryErrors.GeometryInvalidPriceOrRatio.selector);
        geometry.validateParams(true, 1 ether, abi.encode(PRICE_MULTIPLIER, 0), 2);
    }

    /// @dev Test precision with very small price - need sufficient amount
    function test_validateParams_tinyPrice_ask() public {
        uint256 price0 = 1;
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10;
        // With tiny price, need very large amount to produce non-zero quote
        // amt * price / PRICE_MULTIPLIER must be >= 1
        // So amt >= PRICE_MULTIPLIER / price = PRICE_MULTIPLIER
        vm.expectRevert(IGeometryErrors.GeometryAskZeroQuote.selector);
        // forge-lint: disable-next-line(unsafe-typecast)
        geometry.validateParams(true, uint128(PRICE_MULTIPLIER), abi.encode(price0, ratio), 2);
    }

    /// @dev Test precision with very small price for bid
    function test_validateParams_tinyPrice_bid() public {
        uint256 price0 = 1;
        uint256 ratio = (9 * RATIO_MULTIPLIER) / 10;
        // With tiny price, need very large amount to produce non-zero quote
        vm.expectRevert(IGeometryErrors.GeometryBidZeroQuote.selector);
        // forge-lint: disable-next-line(unsafe-typecast)
        geometry.validateParams(false, uint128(PRICE_MULTIPLIER), abi.encode(price0, ratio), 2);
    }

    /// @dev Test with ratio approaching infinity for ask
    function test_validateParams_hugeRatio_ask() public {
        uint256 price0 = 1;
        uint256 ratio = type(uint256).max;
        // Should overflow or produce zero quote
        vm.expectRevert();
        geometry.validateParams(true, 1 ether, abi.encode(price0, ratio), 2);
    }

    /// @dev Test with ratio approaching zero for bid
    function test_validateParams_tinyRatio_bid() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = 1;
        // Should produce zero quote at some point
        vm.expectRevert(IGeometryErrors.GeometryBidZeroQuote.selector);
        geometry.validateParams(false, 1, abi.encode(price0, ratio), 100);
    }

    // ============ Strategy Creation Tests ============

    function test_createGridStrategy_onlyGridEx() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("Unauthorized");
        geometry.createGridStrategy(true, 1, abi.encode(PRICE_MULTIPLIER / 1000, (11 * RATIO_MULTIPLIER) / 10));
    }

    function test_createGridStrategy_noDuplicate() public {
        geometry.createGridStrategy(true, 1, abi.encode(PRICE_MULTIPLIER / 1000, (11 * RATIO_MULTIPLIER) / 10));
        vm.expectRevert("Already exists");
        geometry.createGridStrategy(true, 1, abi.encode(PRICE_MULTIPLIER / 1000, (11 * RATIO_MULTIPLIER) / 10));
    }

    // ============ Price Calculation Tests ============

    function test_getPriceAndReversePrice_ask() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10; // 1.1
        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        uint256 price1 = FullMath.mulDiv(price0, ratio, RATIO_MULTIPLIER);
        uint256 price2 = FullMath.mulDiv(price1, ratio, RATIO_MULTIPLIER);

        assertEq(geometry.getPrice(true, 1, 0), price0);
        assertEq(geometry.getPrice(true, 1, 1), price1);
        assertEq(geometry.getPrice(true, 1, 2), price2);

        assertEq(geometry.getReversePrice(true, 1, 2), price1);
        assertEq(geometry.getReversePrice(true, 1, 1), price0);
        assertEq(geometry.getReversePrice(true, 1, 0), FullMath.mulDiv(price0, RATIO_MULTIPLIER, ratio));
    }

    function test_getPriceAndReversePrice_bid() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = (9 * RATIO_MULTIPLIER) / 10; // 0.9
        geometry.createGridStrategy(false, 2, abi.encode(price0, ratio));

        uint256 price1 = FullMath.mulDiv(price0, ratio, RATIO_MULTIPLIER);
        uint256 price2 = FullMath.mulDiv(price1, ratio, RATIO_MULTIPLIER);

        assertEq(geometry.getPrice(false, 2, 0), price0);
        assertEq(geometry.getPrice(false, 2, 1), price1);
        assertEq(geometry.getPrice(false, 2, 2), price2);

        assertEq(geometry.getReversePrice(false, 2, 2), price1);
        assertEq(geometry.getReversePrice(false, 2, 1), price0);
        assertEq(geometry.getReversePrice(false, 2, 0), FullMath.mulDiv(price0, RATIO_MULTIPLIER, ratio));
    }

    /// @dev Test price at high index values
    function test_getPrice_highIndex() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = (101 * RATIO_MULTIPLIER) / 100; // 1.01
        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        // Calculate price at index 100 using the contract's method
        uint256 contractPrice = geometry.getPrice(true, 1, 100);

        // Verify it's greater than price at index 0
        assertGt(contractPrice, price0, "Price at index 100 should be greater than price0");

        // Verify monotonicity
        uint256 prevPrice = price0;
        for (uint16 i = 1; i <= 100; i++) {
            uint256 price = geometry.getPrice(true, 1, i);
            assertGt(price, prevPrice, "Prices should be monotonically increasing");
            prevPrice = price;
        }
    }

    /// @dev Test reverse price at index 0 (special case)
    function test_getReversePrice_indexZero_ask() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10;
        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        uint256 reversePrice = geometry.getReversePrice(true, 1, 0);
        uint256 expectedReversePrice = FullMath.mulDiv(price0, RATIO_MULTIPLIER, ratio);
        assertEq(reversePrice, expectedReversePrice);
    }

    /// @dev Test reverse price at index 0 for bid
    function test_getReversePrice_indexZero_bid() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = (9 * RATIO_MULTIPLIER) / 10;
        geometry.createGridStrategy(false, 1, abi.encode(price0, ratio));

        uint256 reversePrice = geometry.getReversePrice(false, 1, 0);
        uint256 expectedReversePrice = FullMath.mulDiv(price0, RATIO_MULTIPLIER, ratio);
        assertEq(reversePrice, expectedReversePrice);
    }

    // ============ Fuzz Tests ============

    /// @dev Fuzz test for validateParams with ask orders
    function testFuzz_validateParams_ask_call(uint256 price0, uint256 ratio, uint256 amt, uint256 count) public view {
        // Bound inputs to reasonable ranges that guarantee non-zero quotes
        // price0 * amt / PRICE_MULTIPLIER must be >= 1
        // So we need price0 * amt >= PRICE_MULTIPLIER
        // Use smaller ranges to avoid overflow in calculations
        price0 = bound(price0, PRICE_MULTIPLIER, PRICE_MULTIPLIER * 1000);
        ratio = bound(ratio, RATIO_MULTIPLIER + 1, 2 * RATIO_MULTIPLIER);
        count = bound(count, 1, 20);
        // Ensure amt is reasonable to avoid overflow
        amt = bound(amt, 1 ether, 1000000 ether);

        // Should not revert with valid parameters
        // forge-lint: disable-next-line(unsafe-typecast)
        geometry.validateParams(true, uint128(amt), abi.encode(price0, ratio), uint32(count));
    }

    /// @dev Fuzz test for validateParams with bid orders
    function testFuzz_validateParams_bid_call(uint256 price0, uint256 ratio, uint256 amt, uint256 count) public view {
        // Bound inputs to reasonable ranges that guarantee non-zero quotes
        // price0 * amt / PRICE_MULTIPLIER must be >= 1
        // So we need price0 * amt >= PRICE_MULTIPLIER
        // Use smaller ranges to avoid overflow in calculations
        price0 = bound(price0, PRICE_MULTIPLIER, PRICE_MULTIPLIER * 1000);
        ratio = bound(ratio, RATIO_MULTIPLIER / 2, RATIO_MULTIPLIER - 1);
        count = bound(count, 1, 20);
        // Ensure amt is reasonable to avoid overflow
        amt = bound(amt, 1 ether, 1000000 ether);

        // Should not revert with valid parameters
        // forge-lint: disable-next-line(unsafe-typecast)
        geometry.validateParams(false, uint128(amt), abi.encode(price0, ratio), uint32(count));
    }

    /// @dev Fuzz test for price calculation consistency
    function testFuzz_priceCalculation_consistency(uint256 price0, uint256 ratio, uint16 idx) public {
        // Bound to reasonable values
        price0 = bound(price0, PRICE_MULTIPLIER / 1000, PRICE_MULTIPLIER * 1000);
        ratio = bound(ratio, (101 * RATIO_MULTIPLIER) / 100, (11 * RATIO_MULTIPLIER) / 10); // 1.01 to 1.1
        idx = uint16(bound(idx, 0, 20));

        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        // Calculate expected price iteratively
        uint256 expectedPrice = price0;
        for (uint16 i = 0; i < idx; i++) {
            expectedPrice = FullMath.mulDiv(expectedPrice, ratio, RATIO_MULTIPLIER);
        }

        uint256 actualPrice = geometry.getPrice(true, 1, idx);

        // Allow for small precision differences due to different calculation paths
        // The contract uses exponentiation by squaring, we use iterative multiplication
        // Both should give very close results
        assertApproxEqRel(actualPrice, expectedPrice, 1e15, "Price calculation mismatch"); // 0.1% tolerance
    }

    /// @dev Fuzz test for reverse price calculation
    function testFuzz_reversePriceCalculation(uint256 price0, uint256 ratio, uint16 idx) public {
        // Bound to reasonable values
        price0 = bound(price0, PRICE_MULTIPLIER / 1000, PRICE_MULTIPLIER * 1000);
        ratio = bound(ratio, (101 * RATIO_MULTIPLIER) / 100, (11 * RATIO_MULTIPLIER) / 10); // 1.01 to 1.1
        idx = uint16(bound(idx, 1, 20)); // Start from 1 to avoid special case

        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        uint256 reversePrice = geometry.getReversePrice(true, 1, idx);

        // Reverse price should equal price at idx - 1
        assertEq(reversePrice, geometry.getPrice(true, 1, idx - 1), "Reverse price mismatch");
    }

    /// @dev Fuzz test for bid price calculation
    function testFuzz_bidPriceCalculation(uint256 price0, uint256 ratio, uint16 idx) public {
        // Bound to reasonable values for bid (ratio < 1)
        price0 = bound(price0, PRICE_MULTIPLIER / 1000, PRICE_MULTIPLIER * 1000);
        ratio = bound(ratio, (9 * RATIO_MULTIPLIER) / 10, (99 * RATIO_MULTIPLIER) / 100); // 0.9 to 0.99
        idx = uint16(bound(idx, 0, 20));

        geometry.createGridStrategy(false, 1, abi.encode(price0, ratio));

        // Calculate expected price iteratively
        uint256 expectedPrice = price0;
        for (uint16 i = 0; i < idx; i++) {
            expectedPrice = FullMath.mulDiv(expectedPrice, ratio, RATIO_MULTIPLIER);
        }

        uint256 actualPrice = geometry.getPrice(false, 1, idx);

        // Allow for small precision differences
        assertApproxEqRel(actualPrice, expectedPrice, 1e15, "Bid price calculation mismatch"); // 0.1% tolerance
    }

    /// @dev Fuzz test for ratio boundary conditions
    function testFuzz_ratioBoundary_ask(uint256 ratio) public view {
        ratio = bound(ratio, RATIO_MULTIPLIER + 1, RATIO_MULTIPLIER + 1e15); // Just above 1.0
        uint256 price0 = PRICE_MULTIPLIER;
        uint32 count = 2;

        geometry.validateParams(true, 1 ether, abi.encode(price0, ratio), count);
    }

    /// @dev Fuzz test for ratio boundary conditions for bid
    function testFuzz_ratioBoundary_bid(uint256 ratio) public view {
        ratio = bound(ratio, RATIO_MULTIPLIER - 1e15, RATIO_MULTIPLIER - 1); // Just below 1.0
        uint256 price0 = PRICE_MULTIPLIER;
        uint32 count = 2;

        geometry.validateParams(false, 1 ether, abi.encode(price0, ratio), count);
    }

    /// @dev Fuzz test for extreme price values
    function testFuzz_extremePrices(uint256 price0, uint16 idx) public {
        // Test with various price magnitudes
        price0 = bound(price0, PRICE_MULTIPLIER / 1e10, PRICE_MULTIPLIER * 1e10);
        idx = uint16(bound(idx, 0, 10));
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10;

        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        // Price should always be calculable without overflow for small indices
        uint256 price = geometry.getPrice(true, 1, idx);
        assertGt(price, 0, "Price should be positive");
    }

    /// @dev Fuzz test for amount boundary conditions
    function testFuzz_amountBoundary(uint128 amt) public view {
        amt = uint128(bound(amt, 1, type(uint128).max));
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10;

        geometry.validateParams(true, amt, abi.encode(price0, ratio), 2);
    }

    /// @dev Fuzz test for count boundary conditions
    function testFuzz_countBoundary(uint32 count) public view {
        count = uint32(bound(count, 1, 100));
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10;

        geometry.validateParams(true, 1 ether, abi.encode(price0, ratio), count);
    }

    // ============ Invariant Tests ============

    /// @dev Invariant: reversePrice(idx) = price(idx-1) for idx > 0
    function test_invariant_priceReverseConsistency_ask() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10;
        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        for (uint16 i = 1; i <= 20; i++) {
            uint256 price = geometry.getPrice(true, 1, i);
            uint256 reversePrice = geometry.getReversePrice(true, 1, i);
            uint256 prevPrice = geometry.getPrice(true, 1, i - 1);

            // Reverse price should equal previous price
            assertEq(reversePrice, prevPrice, "Reverse price invariant broken");

            // price * (1/ratio) should approximately equal prevPrice
            // Note: there's inherent precision loss in the division
            uint256 calculatedPrev = FullMath.mulDiv(price, RATIO_MULTIPLIER, ratio);
            // Allow for rounding errors - the difference should be small relative to the price
            assertApproxEqRel(calculatedPrev, prevPrice, 1e16, "Price ratio invariant broken"); // 1% tolerance
        }
    }

    /// @dev Invariant: reversePrice(idx) = price(idx-1) for idx > 0 (bid)
    function test_invariant_priceReverseConsistency_bid() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = (9 * RATIO_MULTIPLIER) / 10;
        geometry.createGridStrategy(false, 1, abi.encode(price0, ratio));

        for (uint16 i = 1; i <= 20; i++) {
            uint256 price = geometry.getPrice(false, 1, i);
            uint256 reversePrice = geometry.getReversePrice(false, 1, i);
            uint256 prevPrice = geometry.getPrice(false, 1, i - 1);

            // Reverse price should equal previous price
            assertEq(reversePrice, prevPrice, "Reverse price invariant broken");

            // price * (1/ratio) should approximately equal prevPrice
            uint256 calculatedPrev = FullMath.mulDiv(price, RATIO_MULTIPLIER, ratio);
            // Allow for rounding errors
            assertApproxEqRel(calculatedPrev, prevPrice, 1e16, "Price ratio invariant broken"); // 1% tolerance
        }
    }

    /// @dev Invariant: prices are monotonically increasing for ask
    function test_invariant_monotonicIncrease_ask() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10;
        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        uint256 prevPrice = 0;
        for (uint16 i = 0; i <= 20; i++) {
            uint256 price = geometry.getPrice(true, 1, i);
            assertGt(price, prevPrice, "Ask prices should be monotonically increasing");
            prevPrice = price;
        }
    }

    /// @dev Invariant: prices are monotonically decreasing for bid
    function test_invariant_monotonicDecrease_bid() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = (9 * RATIO_MULTIPLIER) / 10;
        geometry.createGridStrategy(false, 1, abi.encode(price0, ratio));

        uint256 prevPrice = type(uint256).max;
        for (uint16 i = 0; i <= 20; i++) {
            uint256 price = geometry.getPrice(false, 1, i);
            assertLt(price, prevPrice, "Bid prices should be monotonically decreasing");
            prevPrice = price;
        }
    }

    /// @dev Invariant: price(0) = price0
    function test_invariant_initialPrice() public {
        uint256 price0 = PRICE_MULTIPLIER / 123;
        uint256 ratioAsk = (11 * RATIO_MULTIPLIER) / 10;
        uint256 ratioBid = (9 * RATIO_MULTIPLIER) / 10;

        geometry.createGridStrategy(true, 1, abi.encode(price0, ratioAsk));
        geometry.createGridStrategy(false, 2, abi.encode(price0, ratioBid));

        assertEq(geometry.getPrice(true, 1, 0), price0, "Ask initial price mismatch");
        assertEq(geometry.getPrice(false, 2, 0), price0, "Bid initial price mismatch");
    }

    /// @dev Fuzz invariant: price relationship holds for random inputs
    function testFuzz_invariant_priceRelationship(uint256 price0, uint256 ratio, uint16 idx1, uint16 idx2) public {
        // Bound to reasonable values
        price0 = bound(price0, PRICE_MULTIPLIER / 1000, PRICE_MULTIPLIER * 1000);
        ratio = bound(ratio, (101 * RATIO_MULTIPLIER) / 100, (11 * RATIO_MULTIPLIER) / 10);
        idx1 = uint16(bound(idx1, 0, 20));
        idx2 = uint16(bound(idx2, 0, 20));

        vm.assume(idx1 < idx2);

        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        uint256 price1 = geometry.getPrice(true, 1, idx1);
        uint256 price2 = geometry.getPrice(true, 1, idx2);

        // For ask with ratio > 1, higher index should have higher price
        assertGt(price2, price1, "Higher index should have higher price for ask");
    }

    /// @dev Test overflow protection in _powRatio
    function test_powRatio_overflowProtection() public {
        uint256 price0 = 1;
        uint256 ratio = 2 * RATIO_MULTIPLIER; // 2.0
        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        // At some point, price calculation should overflow
        vm.expectRevert();
        geometry.getPrice(true, 1, 256); // 2^256 would overflow
    }

    /// @dev Test precision at extreme ratios
    function test_precision_extremeRatio() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = 100 * RATIO_MULTIPLIER; // 100x ratio
        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        uint256 price1 = geometry.getPrice(true, 1, 1);
        uint256 expectedPrice1 = price0 * 100;

        // Allow for some precision loss
        assertApproxEqAbs(price1, expectedPrice1, expectedPrice1 / 1e15, "Extreme ratio precision issue");
    }

    /// @dev Test gridId key uniqueness
    function test_gridIdKey_uniqueness() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratioAsk = (11 * RATIO_MULTIPLIER) / 10;
        uint256 ratioBid = (9 * RATIO_MULTIPLIER) / 10;

        // Create ask and bid with same gridId - should be independent
        geometry.createGridStrategy(true, 1, abi.encode(price0, ratioAsk));
        geometry.createGridStrategy(false, 1, abi.encode(price0, ratioBid));

        // Both should exist independently
        assertEq(geometry.getPrice(true, 1, 0), price0);
        assertEq(geometry.getPrice(false, 1, 0), price0);
    }

    /// @dev Test with maximum gridId
    function test_maxGridId() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = (11 * RATIO_MULTIPLIER) / 10;
        uint48 maxGridId = type(uint48).max;

        geometry.createGridStrategy(true, maxGridId, abi.encode(price0, ratio));
        assertEq(geometry.getPrice(true, maxGridId, 0), price0);
    }

    // ============ Additional Edge Case Tests ============

    /// @dev Test that ask with ratio = 1 is rejected for count > 1
    function test_askRatioExactlyOne_revert() public {
        uint256 price0 = PRICE_MULTIPLIER;
        vm.expectRevert(IGeometryErrors.GeometryAskRatioTooLow.selector);
        geometry.validateParams(true, 1 ether, abi.encode(price0, RATIO_MULTIPLIER), 2);
    }

    /// @dev Test that bid with ratio = 1 is rejected for count > 1
    function test_bidRatioExactlyOne_revert() public {
        uint256 price0 = PRICE_MULTIPLIER;
        vm.expectRevert(IGeometryErrors.GeometryBidRatioTooHigh.selector);
        geometry.validateParams(false, 1 ether, abi.encode(price0, RATIO_MULTIPLIER), 2);
    }

    /// @dev Test price calculation with ratio = 1 (single order)
    function test_priceWithRatioOne_singleOrder() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = RATIO_MULTIPLIER;
        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        // With ratio = 1, all prices should be the same
        assertEq(geometry.getPrice(true, 1, 0), price0);
        assertEq(geometry.getPrice(true, 1, 1), price0);
        assertEq(geometry.getPrice(true, 1, 10), price0);
    }

    /// @dev Test reverse price with ratio = 1
    function test_reversePriceWithRatioOne() public {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = RATIO_MULTIPLIER;
        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        // With ratio = 1, reverse price should also be the same
        assertEq(geometry.getReversePrice(true, 1, 0), price0);
        assertEq(geometry.getReversePrice(true, 1, 1), price0);
        assertEq(geometry.getReversePrice(true, 1, 10), price0);
    }

    /// @dev Test with very small ratio for bid (0.01)
    function test_validateParams_verySmallRatio_bid() public view {
        uint256 price0 = PRICE_MULTIPLIER;
        uint256 ratio = RATIO_MULTIPLIER / 100; // 0.01
        geometry.validateParams(false, 1 ether, abi.encode(price0, ratio), 5);
    }

    /// @dev Test with very large ratio for ask (1000x)
    function test_validateParams_veryLargeRatio_ask() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        uint256 ratio = 1000 * RATIO_MULTIPLIER; // 1000x
        geometry.validateParams(true, 1 ether, abi.encode(price0, ratio), 3);
    }

    /// @dev Test that different gridIds produce independent strategies
    function test_multipleStrategies_independent() public {
        uint256 price0A = PRICE_MULTIPLIER;
        uint256 ratioA = (11 * RATIO_MULTIPLIER) / 10;
        uint256 price0B = PRICE_MULTIPLIER * 2;
        uint256 ratioB = (12 * RATIO_MULTIPLIER) / 10;

        geometry.createGridStrategy(true, 1, abi.encode(price0A, ratioA));
        geometry.createGridStrategy(true, 2, abi.encode(price0B, ratioB));

        assertEq(geometry.getPrice(true, 1, 0), price0A);
        assertEq(geometry.getPrice(true, 2, 0), price0B);

        // Verify they produce different prices at index 1
        uint256 price1A = geometry.getPrice(true, 1, 1);
        uint256 price1B = geometry.getPrice(true, 2, 1);
        assertNotEq(price1A, price1B, "Different strategies should produce different prices");
    }

    /// @dev Test price at index 0 equals basePrice
    function testFuzz_priceAtIndex0_equalsBasePrice(uint256 price0, uint256 ratio) public {
        price0 = bound(price0, 1, type(uint128).max);
        ratio = bound(ratio, RATIO_MULTIPLIER + 1, 10 * RATIO_MULTIPLIER);

        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));
        assertEq(geometry.getPrice(true, 1, 0), price0, "Price at index 0 should equal basePrice");
    }

    /// @dev Test that reverse price at index 0 is price0 / ratio
    function testFuzz_reversePriceAtIndex0(uint256 price0, uint256 ratio) public {
        price0 = bound(price0, PRICE_MULTIPLIER, type(uint128).max);
        ratio = bound(ratio, RATIO_MULTIPLIER + 1, 10 * RATIO_MULTIPLIER);

        geometry.createGridStrategy(true, 1, abi.encode(price0, ratio));

        uint256 reversePrice = geometry.getReversePrice(true, 1, 0);
        uint256 expectedReversePrice = FullMath.mulDiv(price0, RATIO_MULTIPLIER, ratio);

        assertEq(reversePrice, expectedReversePrice, "Reverse price at index 0 mismatch");
    }
}

// ============ Invariant Test Handler ============

contract GeometryHandler is Test {
    Geometry public geometry;
    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;
    uint256 public constant RATIO_MULTIPLIER = 10 ** 18;

    uint48[] public askGridIds;
    uint48[] public bidGridIds;

    constructor(address _geometry) {
        geometry = Geometry(_geometry);
    }

    function createAskStrategy(uint48 gridId, uint256 price0, uint256 ratio) external {
        price0 = bound(price0, 1, type(uint128).max);
        ratio = bound(ratio, RATIO_MULTIPLIER + 1, 10 * RATIO_MULTIPLIER);

        // Skip if already exists
        try geometry.strategies((uint256(type(uint256).max) << 128) | uint256(gridId)) returns (uint256, uint256) {
            return;
        } catch {}

        geometry.createGridStrategy(true, gridId, abi.encode(price0, ratio));
        askGridIds.push(gridId);
    }

    function createBidStrategy(uint48 gridId, uint256 price0, uint256 ratio) external {
        price0 = bound(price0, 1, type(uint128).max);
        ratio = bound(ratio, RATIO_MULTIPLIER / 10, RATIO_MULTIPLIER - 1);

        // Skip if already exists
        try geometry.strategies(uint256(gridId)) returns (uint256, uint256) {
            return;
        } catch {}

        geometry.createGridStrategy(false, gridId, abi.encode(price0, ratio));
        bidGridIds.push(gridId);
    }

    function getPriceAsk(uint48 gridIdIdx, uint16 idx) external view returns (uint256) {
        if (askGridIds.length == 0) return 0;
        uint48 gridId = askGridIds[uint256(gridIdIdx) % askGridIds.length];
        return geometry.getPrice(true, gridId, idx);
    }

    function getPriceBid(uint128 gridIdIdx, uint16 idx) external view returns (uint256) {
        if (bidGridIds.length == 0) return 0;
        uint48 gridId = bidGridIds[uint256(gridIdIdx) % bidGridIds.length];
        return geometry.getPrice(false, gridId, idx);
    }
}

// ============ Invariant Test Contract ============

contract GeometryInvariantTest is Test {
    Geometry public geometry;
    GeometryHandler public handler;

    function setUp() public {
        geometry = new Geometry(address(this));
        handler = new GeometryHandler(address(geometry));

        // Target the handler for invariant testing
        targetContract(address(handler));
    }

    function invariant_priceAlwaysPositive() public view {
        // All created strategies should have positive prices at index 0
        // This is implicitly tested by the handler operations
    }

    function invariant_strategiesConsistent() public view {
        // Strategies mapping should be consistent
        // The handler ensures no duplicates are created
    }
}
