// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {GridEx} from "../src/GridEx.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

/// @title LinearTest
/// @notice Tests for Linear strategy edge cases including negative gaps, overflow scenarios
contract LinearTest is Test {
    Linear public linear;
    GridEx public exchange;
    WETH public weth;
    USDC public usdc;
    SEA public sea;
    address public vault = address(0x0888880);
    
    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;

    function setUp() public {
        weth = new WETH();
        usdc = new USDC();
        sea = new SEA();
        exchange = new GridEx(address(weth), address(usdc), vault);
        linear = new Linear(address(exchange));
    }

    // ============ validateParams Tests - Ask Orders ============

    /// @notice Test valid ask order parameters
    function test_validateParams_askValid() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000; // 0.001
        int256 gap = int256(price0 / 10); // 0.0001 (positive for ask)
        bytes memory data = abi.encode(price0, gap);
        
        // Should not revert
        linear.validateParams(true, 1 ether, data, 10);
    }

    /// @notice Test ask order with zero count reverts
    function test_validateParams_askZeroCount() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        int256 gap = int256(price0 / 10);
        bytes memory data = abi.encode(price0, gap);
        
        vm.expectRevert();
        linear.validateParams(true, 1 ether, data, 0);
    }

    /// @notice Test ask order with zero price reverts
    function test_validateParams_askZeroPrice() public {
        int256 gap = 1000;
        bytes memory data = abi.encode(uint256(0), gap);
        
        vm.expectRevert();
        linear.validateParams(true, 1 ether, data, 10);
    }

    /// @notice Test ask order with zero gap reverts
    function test_validateParams_askZeroGap() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        bytes memory data = abi.encode(price0, int256(0));
        
        vm.expectRevert();
        linear.validateParams(true, 1 ether, data, 10);
    }

    /// @notice Test ask order with negative gap reverts (ask requires positive gap)
    function test_validateParams_askNegativeGap() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        int256 gap = -int256(price0 / 10); // negative gap
        bytes memory data = abi.encode(price0, gap);
        
        vm.expectRevert();
        linear.validateParams(true, 1 ether, data, 10);
    }

    /// @notice Test ask order with gap >= price reverts
    function test_validateParams_askGapTooLarge() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        int256 gap = int256(price0); // gap == price0
        bytes memory data = abi.encode(price0, gap);
        
        vm.expectRevert();
        linear.validateParams(true, 1 ether, data, 10);
    }

    /// @notice Test ask order with gap > price reverts
    function test_validateParams_askGapGreaterThanPrice() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        int256 gap = int256(price0 * 2); // gap > price0
        bytes memory data = abi.encode(price0, gap);
        
        vm.expectRevert();
        linear.validateParams(true, 1 ether, data, 10);
    }

    /// @notice Test ask order price overflow scenario - gap must be less than price
    function test_validateParams_askPriceOverflow() public {
        // For ask orders, gap must be < price0, so we can't easily trigger overflow
        // Instead, test that very large price + gap * count stays within bounds
        // This test verifies the L4 check: price0 + (count-1) * gap < uint256.max
        
        // Use a price that's valid (< 1<<128) but with gap that would overflow
        uint256 price0 = (1 << 127); // Large but valid price
        int256 gap = int256((1 << 126)); // Large gap but still < price0
        bytes memory data = abi.encode(price0, gap);
        
        // With 10 orders: price0 + 9 * gap = 2^127 + 9 * 2^126 = 2^127 + 9*2^126
        // This is still within uint256 range, so it won't overflow
        // The L3 check (gap < price0) passes since 2^126 < 2^127
        // Let's verify this doesn't revert (it's a valid configuration)
        linear.validateParams(true, 1 ether, data, 10);
    }

    /// @notice Test ask order with price at boundary (1 << 128)
    function test_validateParams_askPriceAtBoundary() public {
        uint256 price0 = (1 << 128); // exactly at boundary
        int256 gap = 1000;
        bytes memory data = abi.encode(price0, gap);
        
        vm.expectRevert();
        linear.validateParams(true, 1 ether, data, 10);
    }

    /// @notice Test ask order with very small amount that results in zero quote
    function test_validateParams_askZeroQuoteAmount() public {
        uint256 price0 = 1; // very small price
        int256 gap = 1;
        bytes memory data = abi.encode(price0, gap);
        
        // With tiny price and amount, quote amount could be zero
        vm.expectRevert();
        linear.validateParams(true, 1, data, 10);
    }

    // ============ validateParams Tests - Bid Orders ============

    /// @notice Test valid bid order parameters
    function test_validateParams_bidValid() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000; // 0.001
        int256 gap = -int256(price0 / 10); // -0.0001 (negative for bid)
        bytes memory data = abi.encode(price0, gap);
        
        // Should not revert
        linear.validateParams(false, 1 ether, data, 10);
    }

    /// @notice Test bid order with positive gap reverts (bid requires negative gap)
    function test_validateParams_bidPositiveGap() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        int256 gap = int256(price0 / 10); // positive gap
        bytes memory data = abi.encode(price0, gap);
        
        vm.expectRevert();
        linear.validateParams(false, 1 ether, data, 10);
    }

    /// @notice Test bid order where last price becomes negative
    function test_validateParams_bidNegativeLastPrice() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        int256 gap = -int256(price0); // gap magnitude equals price
        bytes memory data = abi.encode(price0, gap);
        
        // With 10 orders: priceLast = price0 + gap * 9 = price0 - price0 * 9 < 0
        vm.expectRevert();
        linear.validateParams(false, 1 ether, data, 10);
    }

    /// @notice Test bid order where last price is exactly zero
    function test_validateParams_bidZeroLastPrice() public {
        // priceLast = 9000 + (-1000) * 9 = 9000 - 9000 = 0
        uint256 exactPrice = 9000;
        int256 exactGap = -1000;
        bytes memory data = abi.encode(exactPrice, exactGap);
        
        vm.expectRevert();
        linear.validateParams(false, 1 ether, data, 10);
    }

    /// @notice Test bid order with very small amount that results in zero quote
    function test_validateParams_bidZeroQuoteAmount() public {
        uint256 price0 = 1; // very small price
        int256 gap = -1;
        bytes memory data = abi.encode(price0, gap);
        
        // With tiny price and amount, quote amount could be zero
        // priceLast = 1 + (-1) * 9 = -8 < 0
        vm.expectRevert();
        linear.validateParams(false, 1, data, 10);
    }

    /// @notice Test bid order with single order (count = 1)
    function test_validateParams_bidSingleOrder() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        int256 gap = -int256(price0 / 2); // large negative gap
        bytes memory data = abi.encode(price0, gap);
        
        // With count = 1, priceLast = price0 + gap * 0 = price0 > 0
        linear.validateParams(false, 1 ether, data, 1);
    }

    // ============ createGridStrategy Tests ============

    /// @notice Test only GridEx can create strategy
    function test_createGridStrategy_onlyGridEx() public {
        bytes memory data = abi.encode(uint256(1000), int256(100));
        
        vm.expectRevert();
        linear.createGridStrategy(true, 1, data);
    }

    /// @notice Test cannot create duplicate strategy
    function test_createGridStrategy_noDuplicate() public {
        bytes memory data = abi.encode(uint256(1000), int256(100));
        
        vm.prank(address(exchange));
        linear.createGridStrategy(true, 1, data);
        
        vm.prank(address(exchange));
        vm.expectRevert();
        linear.createGridStrategy(true, 1, data);
    }

    /// @notice Test ask and bid strategies for same gridId are separate
    function test_createGridStrategy_askBidSeparate() public {
        bytes memory askData = abi.encode(uint256(1000), int256(100));
        bytes memory bidData = abi.encode(uint256(900), int256(-100));
        
        vm.startPrank(address(exchange));
        linear.createGridStrategy(true, 1, askData);
        linear.createGridStrategy(false, 1, bidData);
        vm.stopPrank();
        
        // Both should exist with different prices
        uint256 askPrice = linear.getPrice(true, 1, 0);
        uint256 bidPrice = linear.getPrice(false, 1, 0);
        
        assertEq(askPrice, 1000);
        assertEq(bidPrice, 900);
    }

    // ============ getPrice Tests ============

    /// @notice Test getPrice for ask orders
    function test_getPrice_ask() public {
        uint256 price0 = 1000;
        int256 gap = 100;
        bytes memory data = abi.encode(price0, gap);
        
        vm.prank(address(exchange));
        linear.createGridStrategy(true, 1, data);
        
        assertEq(linear.getPrice(true, 1, 0), 1000);
        assertEq(linear.getPrice(true, 1, 1), 1100);
        assertEq(linear.getPrice(true, 1, 5), 1500);
        assertEq(linear.getPrice(true, 1, 10), 2000);
    }

    /// @notice Test getPrice for bid orders (negative gap)
    function test_getPrice_bid() public {
        uint256 price0 = 1000;
        int256 gap = -100;
        bytes memory data = abi.encode(price0, gap);
        
        vm.prank(address(exchange));
        linear.createGridStrategy(false, 1, data);
        
        assertEq(linear.getPrice(false, 1, 0), 1000);
        assertEq(linear.getPrice(false, 1, 1), 900);
        assertEq(linear.getPrice(false, 1, 5), 500);
        assertEq(linear.getPrice(false, 1, 9), 100);
    }

    // ============ getReversePrice Tests ============

    /// @notice Test getReversePrice for ask orders
    function test_getReversePrice_ask() public {
        uint256 price0 = 1000;
        int256 gap = 100;
        bytes memory data = abi.encode(price0, gap);
        
        vm.prank(address(exchange));
        linear.createGridStrategy(true, 1, data);
        
        // Reverse price is price at idx - 1
        assertEq(linear.getReversePrice(true, 1, 1), 1000); // idx=1 -> price at idx=0
        assertEq(linear.getReversePrice(true, 1, 2), 1100); // idx=2 -> price at idx=1
        assertEq(linear.getReversePrice(true, 1, 5), 1400); // idx=5 -> price at idx=4
    }

    /// @notice Test getReversePrice for bid orders
    function test_getReversePrice_bid() public {
        uint256 price0 = 1000;
        int256 gap = -100;
        bytes memory data = abi.encode(price0, gap);
        
        vm.prank(address(exchange));
        linear.createGridStrategy(false, 1, data);
        
        // Reverse price is price at idx - 1
        assertEq(linear.getReversePrice(false, 1, 1), 1000); // idx=1 -> price at idx=0
        assertEq(linear.getReversePrice(false, 1, 2), 900);  // idx=2 -> price at idx=1
        assertEq(linear.getReversePrice(false, 1, 5), 600);  // idx=5 -> price at idx=4
    }

    /// @notice Test getReversePrice at idx=0 (underflow scenario)
    function test_getReversePrice_idxZero() public {
        uint256 price0 = 1000;
        int256 gap = 100;
        bytes memory data = abi.encode(price0, gap);
        
        vm.prank(address(exchange));
        linear.createGridStrategy(true, 1, data);
        
        // At idx=0, reverse price = price0 + gap * (0 - 1) = price0 - gap
        // For ask with positive gap: 1000 - 100 = 900
        assertEq(linear.getReversePrice(true, 1, 0), 900);
    }

    // ============ Fuzz Tests ============

    /// @notice Fuzz test for ask order price calculation
    function testFuzz_getPrice_ask(uint128 price0, uint64 gap, uint32 idx) public {
        vm.assume(price0 > 0 && price0 < (1 << 127));
        vm.assume(gap > 0 && gap < price0);
        vm.assume(idx < 1000);
        
        // Ensure no overflow
        uint256 maxPrice = uint256(price0) + uint256(gap) * uint256(idx);
        vm.assume(maxPrice < type(uint256).max);
        
        bytes memory data = abi.encode(uint256(price0), int256(uint256(gap)));
        
        vm.prank(address(exchange));
        linear.createGridStrategy(true, 1, data);
        
        uint256 expectedPrice = uint256(price0) + uint256(gap) * uint256(idx);
        assertEq(linear.getPrice(true, 1, idx), expectedPrice);
    }

    /// @notice Fuzz test for bid order price calculation
    function testFuzz_getPrice_bid(uint128 price0, uint64 gap, uint32 idx) public {
        vm.assume(price0 > 0 && price0 < (1 << 127));
        vm.assume(gap > 0 && gap < price0 / 1000); // Ensure gap is small enough
        vm.assume(idx < 1000);
        
        // Ensure price doesn't go negative
        vm.assume(uint256(price0) > uint256(gap) * uint256(idx));
        
        bytes memory data = abi.encode(uint256(price0), -int256(uint256(gap)));
        
        vm.prank(address(exchange));
        linear.createGridStrategy(false, 2, data);
        
        uint256 expectedPrice = uint256(price0) - uint256(gap) * uint256(idx);
        assertEq(linear.getPrice(false, 2, idx), expectedPrice);
    }

    // ============ Edge Case Tests ============

    /// @notice Test with maximum valid gridId
    function test_maxGridId() public {
        uint128 maxGridId = type(uint128).max;
        bytes memory data = abi.encode(uint256(1000), int256(100));
        
        vm.prank(address(exchange));
        linear.createGridStrategy(true, maxGridId, data);
        
        assertEq(linear.getPrice(true, maxGridId, 0), 1000);
    }

    /// @notice Test with very large price values
    function test_largePriceValues() public {
        uint256 price0 = (1 << 127) - 1; // Just under max allowed
        int256 gap = 1;
        bytes memory data = abi.encode(price0, gap);
        
        vm.prank(address(exchange));
        linear.createGridStrategy(true, 1, data);
        
        assertEq(linear.getPrice(true, 1, 0), price0);
        assertEq(linear.getPrice(true, 1, 1), price0 + 1);
    }

    /// @notice Test gridIdKey function behavior
    function test_gridIdKey_separation() public {
        bytes memory data = abi.encode(uint256(1000), int256(100));
        
        vm.startPrank(address(exchange));
        
        // Create strategies for gridId 1 (ask and bid)
        linear.createGridStrategy(true, 1, data);
        linear.createGridStrategy(false, 1, abi.encode(uint256(900), int256(-100)));
        
        // Create strategies for gridId 2
        linear.createGridStrategy(true, 2, abi.encode(uint256(2000), int256(200)));
        linear.createGridStrategy(false, 2, abi.encode(uint256(1800), int256(-200)));
        
        vm.stopPrank();
        
        // Verify all are separate
        assertEq(linear.getPrice(true, 1, 0), 1000);
        assertEq(linear.getPrice(false, 1, 0), 900);
        assertEq(linear.getPrice(true, 2, 0), 2000);
        assertEq(linear.getPrice(false, 2, 0), 1800);
    }
}
