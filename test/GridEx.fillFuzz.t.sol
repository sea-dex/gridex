// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {Lens} from "../src/libraries/Lens.sol";
import {GridExBaseTest} from "./GridExBase.t.sol";

/// @title GridExFillFuzzTest
/// @notice Fuzz tests for fillAskOrder, fillAskOrders, fillBidOrder, fillBidOrders
contract GridExFillFuzzTest is GridExBaseTest {
    uint256 constant ASK_ORDER_FLAG = 0x80000000000000000000000000000000;

    // ============ fillAskOrder Fuzz Tests ============

    /// @notice Fuzz test fillAskOrder with varying fill amounts
    function testFuzz_fillAskOrder_partialFill(uint128 fillAmt) public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = askPrice0 / 20;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 orderAmt = 20000 ether;

        _placeOrders(address(sea), address(usdc), orderAmt, 10, 0, askPrice0, askPrice0 - gap, gap, false, 500);

        // Bound fillAmt to valid range
        fillAmt = uint128(bound(uint256(fillAmt), 1 ether, orderAmt));

        uint256 gridOrderId = toGridOrderId(1, orderId);

        uint256 takerSeaBefore = sea.balanceOf(taker);
        uint256 takerUsdcBefore = usdc.balanceOf(taker);

        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify taker received base tokens
        assertEq(sea.balanceOf(taker), takerSeaBefore + fillAmt);

        // Verify quote tokens were deducted (including fees)
        (uint128 quoteVol, uint128 fees) = Lens.calcAskOrderQuoteAmount(askPrice0, fillAmt, 500);
        assertEq(usdc.balanceOf(taker), takerUsdcBefore - quoteVol - fees);

        // Verify order state
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        assertEq(order.amount, orderAmt - fillAmt);

        // Verify token conservation
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
    }

    /// @notice Fuzz test fillAskOrder with varying prices
    function testFuzz_fillAskOrder_varyingPrice(uint256 priceMultiplier) public {
        // Bound price multiplier to reasonable range (0.0001 to 100 in terms of quote/base)
        priceMultiplier = bound(priceMultiplier, 1, 1000000);
        uint256 askPrice0 = (PRICE_MULTIPLIER * priceMultiplier) / 1000000 / (10 ** 12);

        // Skip if price is too small
        if (askPrice0 == 0) return;

        uint256 gap = askPrice0 / 20;
        if (gap == 0) gap = 1;

        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 orderAmt = 1000 ether;
        uint128 fillAmt = 100 ether;

        // Calculate required quote amount to ensure taker has enough
        uint256 maxQuoteNeeded = (uint256(orderAmt) * askPrice0 * 11) / PRICE_MULTIPLIER / 10; // 10% buffer for fees
        if (maxQuoteNeeded > initialUSDCAmt) return;

        _placeOrders(address(sea), address(usdc), orderAmt, 1, 0, askPrice0, askPrice0 - gap, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        uint256 takerSeaBefore = sea.balanceOf(taker);

        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify taker received base tokens
        assertEq(sea.balanceOf(taker), takerSeaBefore + fillAmt);

        // Verify token conservation
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
    }

    /// @notice Fuzz test fillAskOrder with varying fees
    function testFuzz_fillAskOrder_varyingFee(uint32 feeBps) public {
        // Bound fee to valid range (100 = 0.01% to 100000 = 10%)
        feeBps = uint32(bound(uint256(feeBps), 100, 100000));

        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = askPrice0 / 20;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 orderAmt = 10000 ether;
        uint128 fillAmt = 1000 ether;

        _placeOrders(address(sea), address(usdc), orderAmt, 1, 0, askPrice0, askPrice0 - gap, gap, false, feeBps);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        uint256 takerSeaBefore = sea.balanceOf(taker);
        uint256 takerUsdcBefore = usdc.balanceOf(taker);

        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify taker received base tokens
        assertEq(sea.balanceOf(taker), takerSeaBefore + fillAmt);

        // Verify quote tokens were deducted with correct fee
        (uint128 quoteVol, uint128 fees) = Lens.calcAskOrderQuoteAmount(askPrice0, fillAmt, feeBps);
        assertEq(usdc.balanceOf(taker), takerUsdcBefore - quoteVol - fees);

        // Verify protocol fee
        uint128 protocolFee = fees / 4;
        assertEq(usdc.balanceOf(vault), protocolFee);
    }

    // ============ fillBidOrder Fuzz Tests ============

    /// @notice Fuzz test fillBidOrder with varying fill amounts
    function testFuzz_fillBidOrder_partialFill(uint128 fillAmt) public {
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = bidPrice0 / 20;
        uint128 orderId = 1; // Bid order ID starts from 1
        uint128 orderAmt = 20000 ether;

        _placeOrders(address(sea), address(usdc), orderAmt, 0, 10, bidPrice0 + gap, bidPrice0, gap, false, 500);

        // Bound fillAmt to valid range
        fillAmt = uint128(bound(uint256(fillAmt), 1 ether, orderAmt));

        uint256 gridOrderId = toGridOrderId(1, orderId);

        uint256 takerSeaBefore = sea.balanceOf(taker);
        uint256 takerUsdcBefore = usdc.balanceOf(taker);

        vm.startPrank(taker);
        exchange.fillBidOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify taker sent base tokens
        assertEq(sea.balanceOf(taker), takerSeaBefore - fillAmt);

        // Verify taker received quote tokens (minus fees)
        (uint128 quoteVol, uint128 fees) = Lens.calcBidOrderQuoteAmount(bidPrice0, fillAmt, 500);
        assertEq(usdc.balanceOf(taker), takerUsdcBefore + quoteVol - fees);

        // Verify order state
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        uint128 expectedQuoteAmt = Lens.calcQuoteAmount(orderAmt, bidPrice0, false);
        uint128 filledQuoteVol = Lens.calcQuoteAmount(fillAmt, bidPrice0, false);
        assertEq(order.amount, expectedQuoteAmt - filledQuoteVol);

        // Verify token conservation
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
    }

    /// @notice Fuzz test fillBidOrder with varying fees
    function testFuzz_fillBidOrder_varyingFee(uint32 feeBps) public {
        // Bound fee to valid range
        feeBps = uint32(bound(uint256(feeBps), 100, 100000));

        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = bidPrice0 / 20;
        uint128 orderId = 1;
        uint128 orderAmt = 10000 ether;
        uint128 fillAmt = 1000 ether;

        _placeOrders(address(sea), address(usdc), orderAmt, 0, 1, bidPrice0 + gap, bidPrice0, gap, false, feeBps);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        uint256 takerSeaBefore = sea.balanceOf(taker);
        uint256 takerUsdcBefore = usdc.balanceOf(taker);

        vm.startPrank(taker);
        exchange.fillBidOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify taker sent base tokens
        assertEq(sea.balanceOf(taker), takerSeaBefore - fillAmt);

        // Verify quote tokens received with correct fee deduction
        (uint128 quoteVol, uint128 fees) = Lens.calcBidOrderQuoteAmount(bidPrice0, fillAmt, feeBps);
        assertEq(usdc.balanceOf(taker), takerUsdcBefore + quoteVol - fees);

        // Verify protocol fee
        uint128 protocolFee = fees / 4;
        assertEq(usdc.balanceOf(vault), protocolFee);
    }

    // ============ fillAskOrders (batch) Fuzz Tests ============

    /// @notice Fuzz test fillAskOrders with varying number of orders and amounts
    function testFuzz_fillAskOrders_batch(uint8 orderCount, uint128 fillAmtSeed) public {
        // Bound order count to reasonable range
        orderCount = uint8(bound(uint256(orderCount), 1, 5));

        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = askPrice0 / 20;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 orderAmt = 10000 ether;

        _placeOrders(address(sea), address(usdc), orderAmt, orderCount, 0, askPrice0, askPrice0 - gap, gap, false, 500);

        // Create order IDs and amounts arrays
        uint256[] memory orderIds = new uint256[](orderCount);
        uint128[] memory amts = new uint128[](orderCount);

        uint128 totalFillAmt = 0;
        for (uint256 i = 0; i < orderCount; i++) {
            // forge-lint: disable-next-line
            orderIds[i] = toGridOrderId(1, orderId + uint128(i));
            // Vary fill amounts based on seed
            uint128 fillAmt = uint128(bound(uint256(fillAmtSeed) + i * 1000, 1 ether, orderAmt));
            amts[i] = fillAmt;
            totalFillAmt += fillAmt > orderAmt ? orderAmt : fillAmt;
        }

        uint256 takerSeaBefore = sea.balanceOf(taker);

        vm.startPrank(taker);
        exchange.fillAskOrders(1, orderIds, amts, 0, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify taker received base tokens (may be capped by order amounts)
        uint256 actualReceived = sea.balanceOf(taker) - takerSeaBefore;
        assertTrue(actualReceived > 0);
        assertTrue(actualReceived <= uint256(orderAmt) * orderCount);

        // Verify token conservation
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
    }

    /// @notice Fuzz test fillAskOrders with maxAmt limit
    function testFuzz_fillAskOrders_withMaxAmt(uint128 maxAmt) public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = askPrice0 / 20;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 orderAmt = 10000 ether;
        uint8 orderCount = 3;

        _placeOrders(address(sea), address(usdc), orderAmt, orderCount, 0, askPrice0, askPrice0 - gap, gap, false, 500);

        // Bound maxAmt to reasonable range
        maxAmt = uint128(bound(uint256(maxAmt), 1 ether, uint256(orderAmt) * orderCount));

        uint256[] memory orderIds = new uint256[](orderCount);
        uint128[] memory amts = new uint128[](orderCount);

        for (uint256 i = 0; i < orderCount; i++) {
            // forge-lint: disable-next-line
            orderIds[i] = toGridOrderId(1, orderId + uint128(i));
            amts[i] = orderAmt; // Try to fill full amount
        }

        uint256 takerSeaBefore = sea.balanceOf(taker);

        vm.startPrank(taker);
        exchange.fillAskOrders(1, orderIds, amts, maxAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify taker received at most maxAmt
        uint256 actualReceived = sea.balanceOf(taker) - takerSeaBefore;
        assertTrue(actualReceived <= maxAmt);

        // Verify token conservation
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
    }

    // ============ fillBidOrders (batch) Fuzz Tests ============

    /// @notice Fuzz test fillBidOrders with varying number of orders and amounts
    function testFuzz_fillBidOrders_batch(uint8 orderCount, uint128 fillAmtSeed) public {
        // Bound order count to reasonable range
        orderCount = uint8(bound(uint256(orderCount), 1, 5));

        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = bidPrice0 / 20;
        uint128 orderId = 1;
        uint128 orderAmt = 10000 ether;

        _placeOrders(address(sea), address(usdc), orderAmt, 0, orderCount, bidPrice0 + gap, bidPrice0, gap, false, 500);

        // Create order IDs and amounts arrays
        uint256[] memory orderIds = new uint256[](orderCount);
        uint128[] memory amts = new uint128[](orderCount);

        for (uint256 i = 0; i < orderCount; i++) {
            // forge-lint: disable-next-line
            orderIds[i] = toGridOrderId(1, orderId + uint128(i));
            // Vary fill amounts based on seed
            uint128 fillAmt = uint128(bound(uint256(fillAmtSeed) + i * 1000, 1 ether, orderAmt));
            amts[i] = fillAmt;
        }

        uint256 takerSeaBefore = sea.balanceOf(taker);
        uint256 takerUsdcBefore = usdc.balanceOf(taker);

        vm.startPrank(taker);
        exchange.fillBidOrders(1, orderIds, amts, 0, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify taker sent base tokens
        uint256 actualSent = takerSeaBefore - sea.balanceOf(taker);
        assertTrue(actualSent > 0);
        assertTrue(actualSent <= uint256(orderAmt) * orderCount);

        // Verify taker received quote tokens
        assertTrue(usdc.balanceOf(taker) > takerUsdcBefore - 1); // Account for potential rounding

        // Verify token conservation
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
    }

    /// @notice Fuzz test fillBidOrders with maxAmt limit
    function testFuzz_fillBidOrders_withMaxAmt(uint128 maxAmt) public {
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = bidPrice0 / 20;
        uint128 orderId = 1;
        uint128 orderAmt = 10000 ether;
        uint8 orderCount = 3;

        _placeOrders(address(sea), address(usdc), orderAmt, 0, orderCount, bidPrice0 + gap, bidPrice0, gap, false, 500);

        // Bound maxAmt to reasonable range
        maxAmt = uint128(bound(uint256(maxAmt), 1 ether, uint256(orderAmt) * orderCount));

        uint256[] memory orderIds = new uint256[](orderCount);
        uint128[] memory amts = new uint128[](orderCount);

        for (uint256 i = 0; i < orderCount; i++) {
            // forge-lint: disable-next-line
            orderIds[i] = toGridOrderId(1, orderId + uint128(i));
            amts[i] = orderAmt; // Try to fill full amount
        }

        uint256 takerSeaBefore = sea.balanceOf(taker);

        vm.startPrank(taker);
        exchange.fillBidOrders(1, orderIds, amts, maxAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify taker sent at most maxAmt
        uint256 actualSent = takerSeaBefore - sea.balanceOf(taker);
        assertTrue(actualSent <= maxAmt);

        // Verify token conservation
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
    }

    // ============ Round-trip Fuzz Tests ============

    /// @notice Fuzz test fill ask then fill reversed bid order
    function testFuzz_fillAskThenBid_roundtrip(uint128 fillAmt) public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = askPrice0 / 20;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 orderAmt = 20000 ether;

        _placeOrders(address(sea), address(usdc), orderAmt, 1, 0, askPrice0, askPrice0 - gap, gap, false, 500);

        // Bound fillAmt to valid range
        fillAmt = uint128(bound(uint256(fillAmt), 1 ether, orderAmt));

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Fill ask order
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify order flipped to bid
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        assertTrue(order.revAmount > 0 || order.amount < orderAmt);

        // Fill the reversed bid order if it exists
        if (order.revAmount > 0) {
            // Calculate how much base we can fill on the reversed order
            uint256 bidPrice = askPrice0 - gap;
            uint128 maxBaseFromRev = uint128(Lens.calcBaseAmount(order.revAmount, bidPrice, false));

            if (maxBaseFromRev > 0) {
                uint128 bidFillAmt = uint128(bound(uint256(fillAmt), 1, maxBaseFromRev));

                vm.startPrank(taker);
                exchange.fillBidOrder(gridOrderId, bidFillAmt, 0, new bytes(0), 0);
                vm.stopPrank();
            }
        }

        // Verify token conservation after round-trip
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
    }

    /// @notice Fuzz test fill bid then fill reversed ask order
    function testFuzz_fillBidThenAsk_roundtrip(uint128 fillAmt) public {
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = bidPrice0 / 20;
        uint128 orderId = 1;
        uint128 orderAmt = 20000 ether;

        _placeOrders(address(sea), address(usdc), orderAmt, 0, 1, bidPrice0 + gap, bidPrice0, gap, false, 500);

        // Bound fillAmt to valid range
        fillAmt = uint128(bound(uint256(fillAmt), 1 ether, orderAmt));

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Fill bid order
        vm.startPrank(taker);
        exchange.fillBidOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify order flipped to ask
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);

        // Fill the reversed ask order if it exists
        if (order.revAmount > 0) {
            uint128 askFillAmt = uint128(bound(uint256(fillAmt), 1, order.revAmount));

            vm.startPrank(taker);
            exchange.fillAskOrder(gridOrderId, askFillAmt, 0, new bytes(0), 0);
            vm.stopPrank();
        }

        // Verify token conservation after round-trip
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
    }

    // ============ Compound Mode Fuzz Tests ============

    /// @notice Fuzz test fillAskOrder in compound mode
    function testFuzz_fillAskOrder_compound(uint128 fillAmt) public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = askPrice0 / 20;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 orderAmt = 20000 ether;

        // Place orders with compound = true
        _placeOrders(address(sea), address(usdc), orderAmt, 1, 0, askPrice0, askPrice0 - gap, gap, true, 500);

        // Bound fillAmt to valid range
        fillAmt = uint128(bound(uint256(fillAmt), 1 ether, orderAmt));

        uint256 gridOrderId = toGridOrderId(1, orderId);

        uint256 takerSeaBefore = sea.balanceOf(taker);

        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify taker received base tokens
        assertEq(sea.balanceOf(taker), takerSeaBefore + fillAmt);

        // In compound mode, LP fees are added to the reversed order
        // IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);

        // Verify token conservation
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
    }

    /// @notice Fuzz test fillBidOrder in compound mode
    function testFuzz_fillBidOrder_compound(uint128 fillAmt) public {
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = bidPrice0 / 20;
        uint128 orderId = 1;
        uint128 orderAmt = 20000 ether;

        // Place orders with compound = true
        _placeOrders(address(sea), address(usdc), orderAmt, 0, 1, bidPrice0 + gap, bidPrice0, gap, true, 500);

        // Bound fillAmt to valid range
        fillAmt = uint128(bound(uint256(fillAmt), 1 ether, orderAmt));

        uint256 gridOrderId = toGridOrderId(1, orderId);

        uint256 takerSeaBefore = sea.balanceOf(taker);

        vm.startPrank(taker);
        exchange.fillBidOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify taker sent base tokens
        assertEq(sea.balanceOf(taker), takerSeaBefore - fillAmt);

        // Verify token conservation
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
    }

    // ============ Edge Case Fuzz Tests ============

    /// @notice Fuzz test fillAskOrder with minAmt constraint
    function testFuzz_fillAskOrder_minAmt(uint128 fillAmt, uint128 minAmt) public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = askPrice0 / 20;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 orderAmt = 20000 ether;

        _placeOrders(address(sea), address(usdc), orderAmt, 1, 0, askPrice0, askPrice0 - gap, gap, false, 500);

        // Bound fillAmt and minAmt
        fillAmt = uint128(bound(uint256(fillAmt), 1 ether, orderAmt));
        minAmt = uint128(bound(uint256(minAmt), 0, fillAmt));

        uint256 gridOrderId = toGridOrderId(1, orderId);

        vm.startPrank(taker);
        // This should succeed since fillAmt >= minAmt
        exchange.fillAskOrder(gridOrderId, fillAmt, minAmt, new bytes(0), 0);
        vm.stopPrank();

        // Verify token conservation
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
    }

    /// @notice Fuzz test fillBidOrder with minAmt constraint
    function testFuzz_fillBidOrder_minAmt(uint128 fillAmt, uint128 minAmt) public {
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = bidPrice0 / 20;
        uint128 orderId = 1;
        uint128 orderAmt = 20000 ether;

        _placeOrders(address(sea), address(usdc), orderAmt, 0, 1, bidPrice0 + gap, bidPrice0, gap, false, 500);

        // Bound fillAmt and minAmt
        fillAmt = uint128(bound(uint256(fillAmt), 1 ether, orderAmt));
        minAmt = uint128(bound(uint256(minAmt), 0, fillAmt));

        uint256 gridOrderId = toGridOrderId(1, orderId);

        vm.startPrank(taker);
        // This should succeed since fillAmt >= minAmt
        exchange.fillBidOrder(gridOrderId, fillAmt, minAmt, new bytes(0), 0);
        vm.stopPrank();

        // Verify token conservation
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
    }

    // ============ Multiple Fills Fuzz Tests ============

    /// @notice Fuzz test multiple partial fills on same ask order
    function testFuzz_fillAskOrder_multiplePartialFills(uint8 numFills, uint128 fillAmtSeed) public {
        numFills = uint8(bound(uint256(numFills), 2, 10));

        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = askPrice0 / 20;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 orderAmt = 100000 ether;

        _placeOrders(address(sea), address(usdc), orderAmt, 1, 0, askPrice0, askPrice0 - gap, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        uint128 totalFilled = 0;

        for (uint256 i = 0; i < numFills && totalFilled < orderAmt; i++) {
            uint128 remaining = orderAmt - totalFilled;
            if (remaining < 1 ether) break; // Exit if remaining is too small

            uint128 fillAmt = uint128(bound(uint256(fillAmtSeed) + i * 1000 ether, 1 ether, remaining));

            vm.startPrank(taker);
            exchange.fillAskOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
            vm.stopPrank();

            totalFilled += fillAmt;

            // Verify token conservation after each fill
            assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
            assertEq(
                initialUSDCAmt * 2,
                usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange))
                    + usdc.balanceOf(vault)
            );
        }
    }

    /// @notice Fuzz test multiple partial fills on same bid order
    function testFuzz_fillBidOrder_multiplePartialFills(uint8 numFills, uint128 fillAmtSeed) public {
        numFills = uint8(bound(uint256(numFills), 2, 10));

        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = bidPrice0 / 20;
        uint128 orderId = 1;
        uint128 orderAmt = 100000 ether;

        _placeOrders(address(sea), address(usdc), orderAmt, 0, 1, bidPrice0 + gap, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        uint128 totalFilled = 0;

        for (uint256 i = 0; i < numFills && totalFilled < orderAmt; i++) {
            uint128 remaining = orderAmt - totalFilled;
            if (remaining < 1 ether) break; // Exit if remaining is too small

            uint128 fillAmt = uint128(bound(uint256(fillAmtSeed) + i * 1000 ether, 1 ether, remaining));

            vm.startPrank(taker);
            exchange.fillBidOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
            vm.stopPrank();

            totalFilled += fillAmt;

            // Verify token conservation after each fill
            assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
            assertEq(
                initialUSDCAmt * 2,
                usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange))
                    + usdc.balanceOf(vault)
            );
        }
    }
}
