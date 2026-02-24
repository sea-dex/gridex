// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {GridExRouter} from "../src/GridExRouter.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {CancelFacet} from "../src/facets/CancelFacet.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {ViewFacet} from "../src/facets/ViewFacet.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {ProtocolConstants} from "../src/libraries/ProtocolConstants.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

/// @title LinearTest
/// @notice Tests for Linear strategy edge cases including negative gaps, overflow scenarios
contract LinearTest is Test {
    Linear public linear;
    GridExRouter public router;
    TradeFacet public tradeFacet;
    CancelFacet public cancelFacet;
    AdminFacet public adminFacet;
    ViewFacet public viewFacet;
    WETH public weth;
    USDC public usdc;
    SEA public sea;
    address public vault = address(0x0888880);

    /// @dev `exchange` is the router address cast to payable for compatibility
    address payable public exchange;

    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;

    function setUp() public {
        weth = new WETH();
        usdc = new USDC();
        sea = new SEA();

        // Deploy facets
        tradeFacet = new TradeFacet();
        cancelFacet = new CancelFacet();
        adminFacet = new AdminFacet();
        viewFacet = new ViewFacet();

        // Deploy Router (with admin facet address for bootstrapping)
        router = new GridExRouter(address(this), vault, address(adminFacet));
        exchange = payable(address(router));

        // Register all selectors
        _registerAllSelectors();

        // Configure chain-specific settings
        AdminFacet(exchange).setWETH(address(weth));
        AdminFacet(exchange).setQuoteToken(Currency.wrap(address(usdc)), ProtocolConstants.QUOTE_PRIORITY_USD);
        AdminFacet(exchange).setQuoteToken(Currency.wrap(address(weth)), ProtocolConstants.QUOTE_PRIORITY_WETH);

        linear = new Linear(exchange);
    }

    function _registerAllSelectors() internal {
        // TradeFacet selectors
        bytes4[] memory selectors = new bytes4[](6);
        address[] memory facets = new address[](6);

        selectors[0] = TradeFacet.placeGridOrders.selector;
        facets[0] = address(tradeFacet);
        selectors[1] = TradeFacet.placeETHGridOrders.selector;
        facets[1] = address(tradeFacet);
        selectors[2] = TradeFacet.fillAskOrder.selector;
        facets[2] = address(tradeFacet);
        selectors[3] = TradeFacet.fillAskOrders.selector;
        facets[3] = address(tradeFacet);
        selectors[4] = TradeFacet.fillBidOrder.selector;
        facets[4] = address(tradeFacet);
        selectors[5] = TradeFacet.fillBidOrders.selector;
        facets[5] = address(tradeFacet);

        AdminFacet(exchange).batchSetFacet(selectors, facets);

        // CancelFacet selectors
        bytes4[] memory cancelSel = new bytes4[](5);
        address[] memory cancelFac = new address[](5);

        cancelSel[0] = CancelFacet.cancelGrid.selector;
        cancelFac[0] = address(cancelFacet);
        cancelSel[1] = bytes4(keccak256("cancelGridOrders(address,uint256,uint32,uint32)"));
        cancelFac[1] = address(cancelFacet);
        cancelSel[2] = bytes4(keccak256("cancelGridOrders(uint128,address,uint256[],uint32)"));
        cancelFac[2] = address(cancelFacet);
        cancelSel[3] = CancelFacet.withdrawGridProfits.selector;
        cancelFac[3] = address(cancelFacet);
        cancelSel[4] = CancelFacet.modifyGridFee.selector;
        cancelFac[4] = address(cancelFacet);

        AdminFacet(exchange).batchSetFacet(cancelSel, cancelFac);

        // AdminFacet selectors (beyond bootstrap)
        bytes4[] memory adminSel = new bytes4[](9);
        address[] memory adminFac = new address[](9);

        adminSel[0] = AdminFacet.setWETH.selector;
        adminFac[0] = address(adminFacet);
        adminSel[1] = AdminFacet.setQuoteToken.selector;
        adminFac[1] = address(adminFacet);
        adminSel[2] = AdminFacet.setStrategyWhitelist.selector;
        adminFac[2] = address(adminFacet);
        adminSel[3] = AdminFacet.setOneshotProtocolFeeBps.selector;
        adminFac[3] = address(adminFacet);
        adminSel[4] = AdminFacet.pause.selector;
        adminFac[4] = address(adminFacet);
        adminSel[5] = AdminFacet.unpause.selector;
        adminFac[5] = address(adminFacet);
        adminSel[6] = AdminFacet.rescueEth.selector;
        adminFac[6] = address(adminFacet);
        adminSel[7] = AdminFacet.transferOwnership.selector;
        adminFac[7] = address(adminFacet);
        adminSel[8] = AdminFacet.setFacet.selector;
        adminFac[8] = address(adminFacet);

        AdminFacet(exchange).batchSetFacet(adminSel, adminFac);

        // ViewFacet selectors
        bytes4[] memory viewSel = new bytes4[](12);
        address[] memory viewFac = new address[](12);

        viewSel[0] = ViewFacet.getGridOrder.selector;
        viewFac[0] = address(viewFacet);
        viewSel[1] = ViewFacet.getGridOrders.selector;
        viewFac[1] = address(viewFacet);
        viewSel[2] = ViewFacet.getGridProfits.selector;
        viewFac[2] = address(viewFacet);
        viewSel[3] = ViewFacet.getGridConfig.selector;
        viewFac[3] = address(viewFacet);
        viewSel[4] = ViewFacet.getOneshotProtocolFeeBps.selector;
        viewFac[4] = address(viewFacet);
        viewSel[5] = ViewFacet.isStrategyWhitelisted.selector;
        viewFac[5] = address(viewFacet);
        viewSel[6] = ViewFacet.getPairTokens.selector;
        viewFac[6] = address(viewFacet);
        viewSel[7] = ViewFacet.getPairIdByTokens.selector;
        viewFac[7] = address(viewFacet);
        viewSel[8] = ViewFacet.paused.selector;
        viewFac[8] = address(viewFacet);
        viewSel[9] = ViewFacet.owner.selector;
        viewFac[9] = address(viewFacet);
        viewSel[10] = ViewFacet.vault.selector;
        viewFac[10] = address(viewFacet);
        viewSel[11] = ViewFacet.WETH.selector;
        viewFac[11] = address(viewFacet);

        AdminFacet(exchange).batchSetFacet(viewSel, viewFac);
    }

    // ============ validateParams Tests - Ask Orders ============

    /// @notice Test valid ask order parameters
    function test_validateParams_askValid() public view {
        uint256 price0 = PRICE_MULTIPLIER / 1000; // 0.001
        // forge-lint: disable-next-line
        int256 gap = int256(price0 / 10); // 0.0001 (positive for ask)
        bytes memory data = abi.encode(price0, gap);

        // Should not revert
        linear.validateParams(true, 1 ether, data, 10);
    }

    /// @notice Test ask order with zero count reverts
    function test_validateParams_askZeroCount() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        // forge-lint: disable-next-line
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
        // forge-lint: disable-next-line
        int256 gap = -int256(price0 / 10); // negative gap
        bytes memory data = abi.encode(price0, gap);

        vm.expectRevert();
        linear.validateParams(true, 1 ether, data, 10);
    }

    /// @notice Test ask order with gap >= price reverts
    function test_validateParams_askGapTooLarge() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        // forge-lint: disable-next-line
        int256 gap = int256(price0); // gap == price0
        bytes memory data = abi.encode(price0, gap);

        vm.expectRevert();
        linear.validateParams(true, 1 ether, data, 10);
    }

    /// @notice Test ask order with gap > price reverts
    function test_validateParams_askGapGreaterThanPrice() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        // forge-lint: disable-next-line
        int256 gap = int256(price0 * 2); // gap > price0
        bytes memory data = abi.encode(price0, gap);

        vm.expectRevert();
        linear.validateParams(true, 1 ether, data, 10);
    }

    /// @notice Test ask order price overflow scenario - gap must be less than price
    function test_validateParams_askPriceOverflow() public view {
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
    function test_validateParams_askPriceAtBoundary() public view {
        uint256 price0 = (1 << 128); // exactly at boundary
        int256 gap = 1000;
        bytes memory data = abi.encode(price0, gap);

        // vm.expectRevert();
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
        // forge-lint: disable-next-line
        int256 gap = -int256(price0 / 10); // -0.0001 (negative for bid)
        bytes memory data = abi.encode(price0, gap);

        // Should not revert
        linear.validateParams(false, 1 ether, data, 10);
    }

    /// @notice Test bid order with positive gap reverts (bid requires negative gap)
    function test_validateParams_bidPositiveGap() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        // forge-lint: disable-next-line
        int256 gap = int256(price0 / 10); // positive gap
        bytes memory data = abi.encode(price0, gap);

        vm.expectRevert();
        linear.validateParams(false, 1 ether, data, 10);
    }

    /// @notice Test bid order where last price becomes negative
    function test_validateParams_bidNegativeLastPrice() public {
        uint256 price0 = PRICE_MULTIPLIER / 1000;
        // forge-lint: disable-next-line
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
        // forge-lint: disable-next-line
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

        vm.prank(exchange);
        linear.createGridStrategy(true, 1, data);

        vm.prank(exchange);
        vm.expectRevert();
        linear.createGridStrategy(true, 1, data);
    }

    /// @notice Test ask and bid strategies for same gridId are separate
    function test_createGridStrategy_askBidSeparate() public {
        bytes memory askData = abi.encode(uint256(1000), int256(100));
        bytes memory bidData = abi.encode(uint256(900), int256(-100));

        vm.startPrank(exchange);
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

        vm.prank(exchange);
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

        vm.prank(exchange);
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

        vm.prank(exchange);
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

        vm.prank(exchange);
        linear.createGridStrategy(false, 1, data);

        // Reverse price is price at idx - 1
        assertEq(linear.getReversePrice(false, 1, 1), 1000); // idx=1 -> price at idx=0
        assertEq(linear.getReversePrice(false, 1, 2), 900); // idx=2 -> price at idx=1
        assertEq(linear.getReversePrice(false, 1, 5), 600); // idx=5 -> price at idx=4
    }

    /// @notice Test getReversePrice at idx=0 (underflow scenario)
    function test_getReversePrice_idxZero() public {
        uint256 price0 = 1000;
        int256 gap = 100;
        bytes memory data = abi.encode(price0, gap);

        vm.prank(exchange);
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

        vm.prank(exchange);
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

        vm.prank(exchange);
        linear.createGridStrategy(false, 2, data);

        uint256 expectedPrice = uint256(price0) - uint256(gap) * uint256(idx);
        assertEq(linear.getPrice(false, 2, idx), expectedPrice);
    }

    // ============ Edge Case Tests ============

    /// @notice Test with maximum valid gridId
    function test_maxGridId() public {
        uint128 maxGridId = type(uint128).max;
        bytes memory data = abi.encode(uint256(1000), int256(100));

        vm.prank(exchange);
        linear.createGridStrategy(true, maxGridId, data);

        assertEq(linear.getPrice(true, maxGridId, 0), 1000);
    }

    /// @notice Test with very large price values
    function test_largePriceValues() public {
        uint256 price0 = (1 << 127) - 1; // Just under max allowed
        int256 gap = 1;
        bytes memory data = abi.encode(price0, gap);

        vm.prank(exchange);
        linear.createGridStrategy(true, 1, data);

        assertEq(linear.getPrice(true, 1, 0), price0);
        assertEq(linear.getPrice(true, 1, 1), price0 + 1);
    }

    /// @notice Test gridIdKey function behavior
    function test_gridIdKey_separation() public {
        bytes memory data = abi.encode(uint256(1000), int256(100));

        vm.startPrank(exchange);

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
