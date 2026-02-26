// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {Geometry} from "../src/strategy/Geometry.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {Lens} from "../src/libraries/Lens.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {GridExBaseTest} from "./GridExBase.t.sol";

/// @title GridExMixedStrategyTest
/// @notice Tests for grids with mixed Geometry and Linear strategies
contract GridExMixedStrategyTest is GridExBaseTest {
    Geometry public geometry;
    uint256 internal constant RATIO_MULTIPLIER = 1e18;

    function setUp() public override {
        super.setUp();
        geometry = new Geometry(address(exchange));
        AdminFacet(address(exchange)).setStrategyWhitelist(address(geometry), true);
    }

    /// @notice Helper to place orders with mixed strategies (Geometry for ask, Linear for bid)
    function _placeMixedOrdersGeometryAskLinearBid(
        uint16 askCount,
        uint16 bidCount,
        uint128 baseAmt,
        uint256 askPrice0,
        uint256 askRatio,
        uint256 bidPrice0,
        uint256 bidGap,
        uint32 fee
    ) internal {
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: geometry,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, askRatio),
            bidData: abi.encode(bidPrice0, -int256(bidGap)),
            askOrderCount: askCount,
            bidOrderCount: bidCount,
            baseAmount: baseAmt,
            fee: fee,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        TradeFacet(address(exchange)).placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    /// @notice Helper to place orders with mixed strategies (Linear for ask, Geometry for bid)
    function _placeMixedOrdersLinearAskGeometryBid(
        uint16 askCount,
        uint16 bidCount,
        uint128 baseAmt,
        uint256 askPrice0,
        uint256 askGap,
        uint256 bidPrice0,
        uint256 bidRatio,
        uint32 fee
    ) internal {
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: geometry,
            askData: abi.encode(askPrice0, int256(askGap)),
            bidData: abi.encode(bidPrice0, bidRatio),
            askOrderCount: askCount,
            bidOrderCount: bidCount,
            baseAmount: baseAmt,
            fee: fee,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        TradeFacet(address(exchange)).placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    // ========== Tests: Geometry Ask + Linear Bid ==========

    /// @notice Test placing a grid with Geometry ask and Linear bid strategies
    function test_placeMixedGrid_geometryAskLinearBid() public {
        uint128 baseAmt = 10_000 ether;
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 askRatio = (11 * RATIO_MULTIPLIER) / 10; // 1.1
        uint256 bidPrice0 = askPrice0 / 2; // 0.001
        uint256 bidGap = bidPrice0 / 20; // 0.00005

        _placeMixedOrdersGeometryAskLinearBid(4, 4, baseAmt, askPrice0, askRatio, bidPrice0, bidGap, 500);

        // Verify grid config
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        assertEq(gridConf.askOrderCount, 4);
        assertEq(gridConf.bidOrderCount, 4);
        assertEq(address(gridConf.askStrategy), address(geometry));
        assertEq(address(gridConf.bidStrategy), address(linear));

        // Verify ask orders (geometry)
        uint16 askOrderId0 = 0x8000;
        uint64 gridOrderId0 = toGridOrderId(1, askOrderId0);
        uint64 gridOrderId1 = toGridOrderId(1, askOrderId0 + 1);

        IGridOrder.OrderInfo memory askOrder0 = exchange.getGridOrder(gridOrderId0);
        IGridOrder.OrderInfo memory askOrder1 = exchange.getGridOrder(gridOrderId1);

        assertEq(askOrder0.price, askPrice0);
        assertEq(askOrder1.price, (askPrice0 * askRatio) / RATIO_MULTIPLIER);
        assertEq(askOrder0.amount, baseAmt);
        assertEq(askOrder0.isAsk, true);

        // Verify bid orders (linear)
        uint16 bidOrderId0 = 0;
        uint64 gridBidId0 = toGridOrderId(1, bidOrderId0);
        uint64 gridBidId1 = toGridOrderId(1, bidOrderId0 + 1);

        IGridOrder.OrderInfo memory bidOrder0 = exchange.getGridOrder(gridBidId0);
        IGridOrder.OrderInfo memory bidOrder1 = exchange.getGridOrder(gridBidId1);

        assertEq(bidOrder0.price, bidPrice0);
        assertEq(bidOrder1.price, bidPrice0 - bidGap);
        assertEq(bidOrder0.amount, Lens.calcQuoteAmount(baseAmt, bidPrice0, false));
        assertEq(bidOrder0.isAsk, false);
    }

    /// @notice Test filling a geometry ask order from mixed grid
    function test_fillAskOrder_geometryAskLinearBid() public {
        uint128 baseAmt = 10_000 ether;
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 askRatio = (11 * RATIO_MULTIPLIER) / 10; // 1.1
        uint256 bidPrice0 = askPrice0 / 2;
        uint256 bidGap = bidPrice0 / 20;

        _placeMixedOrdersGeometryAskLinearBid(4, 4, baseAmt, askPrice0, askRatio, bidPrice0, bidGap, 500);

        uint16 askOrderId0 = 0x8000;
        uint64 gridOrderId0 = toGridOrderId(1, askOrderId0);

        IGridOrder.OrderInfo memory orderBefore = exchange.getGridOrder(gridOrderId0);
        assertEq(orderBefore.price, askPrice0);

        // Fill the ask order
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId0, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        // Verify order flipped
        IGridOrder.OrderInfo memory orderAfter = exchange.getGridOrder(gridOrderId0);
        assertEq(orderAfter.amount, 0);
        assertEq(orderAfter.revAmount, Lens.calcQuoteAmount(baseAmt, orderBefore.revPrice, false));

        // Verify balances
        assertEq(initialSEAAmt + baseAmt, sea.balanceOf(taker));
        (uint128 usdcVol, uint128 fees) = Lens.calcAskOrderQuoteAmount(askPrice0, baseAmt, 500);
        assertEq(initialUSDCAmt - usdcVol - fees, usdc.balanceOf(taker));
    }

    /// @notice Test filling a linear bid order from mixed grid
    function test_fillBidOrder_geometryAskLinearBid() public {
        uint128 baseAmt = 10_000 ether;
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 askRatio = (11 * RATIO_MULTIPLIER) / 10; // 1.1
        uint256 bidPrice0 = askPrice0 / 2;
        uint256 bidGap = bidPrice0 / 20;

        _placeMixedOrdersGeometryAskLinearBid(4, 4, baseAmt, askPrice0, askRatio, bidPrice0, bidGap, 500);

        uint16 bidOrderId0 = 0;
        uint64 gridBidId0 = toGridOrderId(1, bidOrderId0);

        IGridOrder.OrderInfo memory orderBefore = exchange.getGridOrder(gridBidId0);
        assertEq(orderBefore.price, bidPrice0);

        // Fill the bid order
        vm.startPrank(taker);
        exchange.fillBidOrder(gridBidId0, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        // Verify order flipped
        IGridOrder.OrderInfo memory orderAfter = exchange.getGridOrder(gridBidId0);
        assertEq(orderAfter.amount, 0);
        assertEq(orderAfter.revAmount, baseAmt);

        // Verify balances
        assertEq(initialSEAAmt - baseAmt, sea.balanceOf(taker));
        (uint128 usdcVol, uint128 fees) = Lens.calcBidOrderQuoteAmount(bidPrice0, baseAmt, 500);
        assertEq(initialUSDCAmt + usdcVol - fees, usdc.balanceOf(taker));
    }

    // ========== Tests: Linear Ask + Geometry Bid ==========

    /// @notice Test placing a grid with Linear ask and Geometry bid strategies
    function test_placeMixedGrid_linearAskGeometryBid() public {
        uint128 baseAmt = 10_000 ether;
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 askGap = askPrice0 / 20; // 0.0001
        uint256 bidPrice0 = askPrice0 / 2; // 0.001
        uint256 bidRatio = (9 * RATIO_MULTIPLIER) / 10; // 0.9

        _placeMixedOrdersLinearAskGeometryBid(4, 4, baseAmt, askPrice0, askGap, bidPrice0, bidRatio, 500);

        // Verify grid config
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        assertEq(gridConf.askOrderCount, 4);
        assertEq(gridConf.bidOrderCount, 4);
        assertEq(address(gridConf.askStrategy), address(linear));
        assertEq(address(gridConf.bidStrategy), address(geometry));

        // Verify ask orders (linear)
        uint16 askOrderId0 = 0x8000;
        uint64 gridOrderId0 = toGridOrderId(1, askOrderId0);
        uint64 gridOrderId1 = toGridOrderId(1, askOrderId0 + 1);

        IGridOrder.OrderInfo memory askOrder0 = exchange.getGridOrder(gridOrderId0);
        IGridOrder.OrderInfo memory askOrder1 = exchange.getGridOrder(gridOrderId1);

        assertEq(askOrder0.price, askPrice0);
        assertEq(askOrder1.price, askPrice0 + askGap);
        assertEq(askOrder0.amount, baseAmt);
        assertEq(askOrder0.isAsk, true);

        // Verify bid orders (geometry)
        uint16 bidOrderId0 = 0;
        uint64 gridBidId0 = toGridOrderId(1, bidOrderId0);
        uint64 gridBidId1 = toGridOrderId(1, bidOrderId0 + 1);

        IGridOrder.OrderInfo memory bidOrder0 = exchange.getGridOrder(gridBidId0);
        IGridOrder.OrderInfo memory bidOrder1 = exchange.getGridOrder(gridBidId1);

        assertEq(bidOrder0.price, bidPrice0);
        assertEq(bidOrder1.price, (bidPrice0 * bidRatio) / RATIO_MULTIPLIER);
        assertEq(bidOrder0.amount, Lens.calcQuoteAmount(baseAmt, bidPrice0, false));
        assertEq(bidOrder0.isAsk, false);
    }

    /// @notice Test filling a linear ask order from mixed grid
    function test_fillAskOrder_linearAskGeometryBid() public {
        uint128 baseAmt = 10_000 ether;
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 askGap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 / 2;
        uint256 bidRatio = (9 * RATIO_MULTIPLIER) / 10;

        _placeMixedOrdersLinearAskGeometryBid(4, 4, baseAmt, askPrice0, askGap, bidPrice0, bidRatio, 500);

        uint16 askOrderId0 = 0x8000;
        uint64 gridOrderId0 = toGridOrderId(1, askOrderId0);

        IGridOrder.OrderInfo memory orderBefore = exchange.getGridOrder(gridOrderId0);
        assertEq(orderBefore.price, askPrice0);

        // Fill the ask order
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId0, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        // Verify order flipped
        IGridOrder.OrderInfo memory orderAfter = exchange.getGridOrder(gridOrderId0);
        assertEq(orderAfter.amount, 0);
        assertEq(orderAfter.revAmount, Lens.calcQuoteAmount(baseAmt, orderBefore.revPrice, false));
    }

    /// @notice Test filling a geometry bid order from mixed grid
    function test_fillBidOrder_linearAskGeometryBid() public {
        uint128 baseAmt = 10_000 ether;
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 askGap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 / 2;
        uint256 bidRatio = (9 * RATIO_MULTIPLIER) / 10;

        _placeMixedOrdersLinearAskGeometryBid(4, 4, baseAmt, askPrice0, askGap, bidPrice0, bidRatio, 500);

        uint16 bidOrderId0 = 0;
        uint64 gridBidId0 = toGridOrderId(1, bidOrderId0);

        IGridOrder.OrderInfo memory orderBefore = exchange.getGridOrder(gridBidId0);
        assertEq(orderBefore.price, bidPrice0);

        // Fill the bid order
        vm.startPrank(taker);
        exchange.fillBidOrder(gridBidId0, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        // Verify order flipped
        IGridOrder.OrderInfo memory orderAfter = exchange.getGridOrder(gridBidId0);
        assertEq(orderAfter.amount, 0);
        assertEq(orderAfter.revAmount, baseAmt);
    }

    // ========== Tests: Multiple Mixed Grids ==========

    /// @notice Test placing multiple grids with different strategy combinations
    function test_multipleMixedGrids() public {
        uint128 baseAmt = 10_000 ether;
        uint256 price0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002

        // Grid 1: Geometry ask + Linear bid
        _placeMixedOrdersGeometryAskLinearBid(
            3, 3, baseAmt, price0, (11 * RATIO_MULTIPLIER) / 10, price0 / 2, price0 / 40, 500
        );

        // Grid 2: Linear ask + Geometry bid
        _placeMixedOrdersLinearAskGeometryBid(
            3, 3, baseAmt, price0, price0 / 20, price0 / 2, (9 * RATIO_MULTIPLIER) / 10, 500
        );

        // Verify grid 1
        IGridOrder.GridConfig memory grid1Conf = exchange.getGridConfig(1);
        assertEq(address(grid1Conf.askStrategy), address(geometry));
        assertEq(address(grid1Conf.bidStrategy), address(linear));

        // Verify grid 2
        IGridOrder.GridConfig memory grid2Conf = exchange.getGridConfig(2);
        assertEq(address(grid2Conf.askStrategy), address(linear));
        assertEq(address(grid2Conf.bidStrategy), address(geometry));

        // Fill orders from both grids
        uint64 grid1AskId = toGridOrderId(1, 0x8000);
        uint64 grid2AskId = toGridOrderId(2, 0x8000);
        uint64 grid1BidId = toGridOrderId(1, 0);
        uint64 grid2BidId = toGridOrderId(2, 0);

        vm.startPrank(taker);
        exchange.fillAskOrder(grid1AskId, baseAmt, baseAmt, new bytes(0), 0);
        exchange.fillAskOrder(grid2AskId, baseAmt, baseAmt, new bytes(0), 0);
        exchange.fillBidOrder(grid1BidId, baseAmt, baseAmt, new bytes(0), 0);
        exchange.fillBidOrder(grid2BidId, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        // Verify all orders are filled
        IGridOrder.OrderInfo memory order1Ask = exchange.getGridOrder(grid1AskId);
        IGridOrder.OrderInfo memory order2Ask = exchange.getGridOrder(grid2AskId);
        IGridOrder.OrderInfo memory order1Bid = exchange.getGridOrder(grid1BidId);
        IGridOrder.OrderInfo memory order2Bid = exchange.getGridOrder(grid2BidId);

        assertEq(order1Ask.amount, 0);
        assertEq(order2Ask.amount, 0);
        assertEq(order1Bid.amount, 0);
        assertEq(order2Bid.amount, 0);
    }

    /// @notice Test batch filling orders from mixed strategy grids
    function test_batchFillMixedGrids() public {
        uint128 baseAmt = 5_000 ether;
        uint256 price0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002

        // Grid 1: Geometry ask + Linear bid
        _placeMixedOrdersGeometryAskLinearBid(
            3, 3, baseAmt, price0, (105 * RATIO_MULTIPLIER) / 100, price0 / 2, price0 / 40, 500
        );

        // Batch fill ask orders (geometry)
        uint16 askOrderId0 = 0x8000;
        uint64[] memory askIds = new uint64[](3);
        askIds[0] = toGridOrderId(1, askOrderId0);
        askIds[1] = toGridOrderId(1, askOrderId0 + 1);
        askIds[2] = toGridOrderId(1, askOrderId0 + 2);

        uint128[] memory askAmts = new uint128[](3);
        askAmts[0] = baseAmt;
        askAmts[1] = baseAmt;
        askAmts[2] = baseAmt;

        vm.startPrank(taker);
        exchange.fillAskOrders(1, askIds, askAmts, baseAmt * 3, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify all ask orders filled
        for (uint256 i = 0; i < 3; i++) {
            IGridOrder.OrderInfo memory order = exchange.getGridOrder(askIds[i]);
            assertEq(order.amount, 0);
            assertTrue(order.revAmount > 0);
        }

        // Batch fill bid orders (linear)
        uint64[] memory bidIds = new uint64[](3);
        bidIds[0] = toGridOrderId(1, 0);
        bidIds[1] = toGridOrderId(1, 1);
        bidIds[2] = toGridOrderId(1, 2);

        uint128[] memory bidAmts = new uint128[](3);
        bidAmts[0] = baseAmt;
        bidAmts[1] = baseAmt;
        bidAmts[2] = baseAmt;

        vm.startPrank(taker);
        exchange.fillBidOrders(1, bidIds, bidAmts, baseAmt * 3, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify all bid orders filled
        for (uint256 i = 0; i < 3; i++) {
            IGridOrder.OrderInfo memory order = exchange.getGridOrder(bidIds[i]);
            assertEq(order.amount, 0);
            assertEq(order.revAmount, baseAmt);
        }
    }

    /// @notice Test order flip and refill in mixed strategy grid
    /// @dev Tests the bid-ask flip mechanism where:
    ///      - Ask orders when filled become bid orders (with quote amount as revAmount)
    ///      - Bid orders when filled become ask orders (with base amount as revAmount)
    ///      - Bid orders store quote amount in their amount field
    ///      - Ask orders store base amount in their amount field
    function test_orderFlipAndRefill_mixedGrid() public {
        uint128 baseAmt = 10_000 ether;
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 askRatio = (11 * RATIO_MULTIPLIER) / 10; // 1.1
        uint256 bidPrice0 = askPrice0 / 2;
        uint256 bidGap = bidPrice0 / 20;

        _placeMixedOrdersGeometryAskLinearBid(2, 2, baseAmt, askPrice0, askRatio, bidPrice0, bidGap, 500);

        uint64 gridAskId = toGridOrderId(1, 0x8000);
        uint64 gridBidId = toGridOrderId(1, 0);

        // === Step 1: Fill ask order (geometry) ===
        vm.startPrank(taker);
        exchange.fillAskOrder(gridAskId, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.OrderInfo memory askOrderAfterFill = exchange.getGridOrder(gridAskId);
        assertEq(askOrderAfterFill.amount, 0, "Ask amount should be 0 after fill");
        assertTrue(askOrderAfterFill.revAmount > 0, "Ask revAmount should be > 0 after fill");

        // === Step 2: Fill the flipped bid order ===
        // After ask fill, the order flips to a bid order with revAmount in quote tokens
        // fillBidOrder takes base amount to sell
        vm.startPrank(taker);
        exchange.fillBidOrder(gridAskId, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.OrderInfo memory askOrderAfterRefill = exchange.getGridOrder(gridAskId);
        assertEq(askOrderAfterRefill.amount, baseAmt, "Ask amount should be restored after bid fill");
        assertEq(askOrderAfterRefill.revAmount, 0, "Ask revAmount should be 0 after bid fill");

        // === Step 3: Fill bid order (linear) ===
        // Bid orders store quote amount in their amount field
        IGridOrder.OrderInfo memory bidOrderBefore = exchange.getGridOrder(gridBidId);
        assertTrue(bidOrderBefore.amount > 0, "Bid order should have quote amount");

        vm.startPrank(taker);
        exchange.fillBidOrder(gridBidId, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.OrderInfo memory bidOrderAfterFill = exchange.getGridOrder(gridBidId);
        assertEq(bidOrderAfterFill.amount, 0, "Bid amount should be 0 after fill");
        assertEq(bidOrderAfterFill.revAmount, baseAmt, "Bid revAmount should equal baseAmt");

        // === Step 4: Fill the flipped ask order ===
        // After bid fill, the order flips to an ask order
        // The amount field now contains the quote amount (from the original bid order)
        // We need to fill with the actual amount in the order
        vm.startPrank(taker);
        exchange.fillAskOrder(gridBidId, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.OrderInfo memory bidOrderAfterRefill = exchange.getGridOrder(gridBidId);
        // After filling the flipped ask order, the amount is the quote amount (not base amount)
        // because bid orders store quote amounts
        assertTrue(bidOrderAfterRefill.amount > 0, "Bid amount should be > 0 after ask fill");
        assertEq(bidOrderAfterRefill.revAmount, 0, "Bid revAmount should be 0 after ask fill");
    }

    /// @notice Test profit calculation for mixed strategy grid
    function test_profitCalculation_mixedGrid() public {
        uint128 baseAmt = 10_000 ether;
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 askRatio = (11 * RATIO_MULTIPLIER) / 10; // 1.1
        uint256 bidPrice0 = askPrice0 / 2;
        uint256 bidGap = bidPrice0 / 20;

        _placeMixedOrdersGeometryAskLinearBid(2, 2, baseAmt, askPrice0, askRatio, bidPrice0, bidGap, 500);

        uint64 gridAskId = toGridOrderId(1, 0x8000);
        uint64 gridBidId = toGridOrderId(1, 0);

        // Record initial balances
        uint256 makerUSDCBefore = usdc.balanceOf(maker);

        // Fill ask order
        vm.startPrank(taker);
        exchange.fillAskOrder(gridAskId, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        // Check grid profits increased
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        assertTrue(gridConf.profits > 0);

        // Fill bid order
        vm.startPrank(taker);
        exchange.fillBidOrder(gridBidId, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        // Check grid profits increased further
        gridConf = exchange.getGridConfig(1);
        uint256 profitsAfterBothFills = gridConf.profits;
        assertTrue(profitsAfterBothFills > 0);

        // Withdraw profits
        vm.startPrank(maker);
        uint256 makerUSDCAfter = usdc.balanceOf(maker);
        exchange.withdrawGridProfits(1, profitsAfterBothFills, maker, 0);
        uint256 makerUSDCFinal = usdc.balanceOf(maker);
        vm.stopPrank();

        assertEq(makerUSDCFinal - makerUSDCAfter, profitsAfterBothFills);
    }

    /// @notice Test partial fill on mixed strategy grid
    function test_partialFill_mixedGrid() public {
        uint128 baseAmt = 10_000 ether;
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 askRatio = (11 * RATIO_MULTIPLIER) / 10; // 1.1
        uint256 bidPrice0 = askPrice0 / 2;
        uint256 bidGap = bidPrice0 / 20;

        _placeMixedOrdersGeometryAskLinearBid(2, 2, baseAmt, askPrice0, askRatio, bidPrice0, bidGap, 500);

        uint64 gridAskId = toGridOrderId(1, 0x8000);
        uint128 partialAmt = baseAmt / 2;

        // Partial fill ask order
        vm.startPrank(taker);
        exchange.fillAskOrder(gridAskId, partialAmt, partialAmt, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.OrderInfo memory orderAfterPartial = exchange.getGridOrder(gridAskId);
        assertEq(orderAfterPartial.amount, baseAmt - partialAmt);
        assertTrue(orderAfterPartial.revAmount > 0);

        // Complete the fill
        vm.startPrank(taker);
        exchange.fillAskOrder(gridAskId, baseAmt - partialAmt, baseAmt - partialAmt, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.OrderInfo memory orderAfterComplete = exchange.getGridOrder(gridAskId);
        assertEq(orderAfterComplete.amount, 0);
    }

    /// @notice Test with different fee values on mixed strategy grid
    function test_differentFees_mixedGrid() public {
        uint128 baseAmt = 10_000 ether;
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 askRatio = (11 * RATIO_MULTIPLIER) / 10; // 1.1
        uint256 bidPrice0 = askPrice0 / 2;
        uint256 bidGap = bidPrice0 / 20;

        // Test with minimum fee (1 bps = 0.01%)
        _placeMixedOrdersGeometryAskLinearBid(1, 1, baseAmt, askPrice0, askRatio, bidPrice0, bidGap, 1);

        uint64 gridAskId = toGridOrderId(1, 0x8000);

        vm.startPrank(taker);
        exchange.fillAskOrder(gridAskId, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        // With minimum fee, profits should come from price spread plus small fee
        assertTrue(gridConf.profits >= 0);

        // Create another grid with higher fee (10% fee = 10000 bps)
        _placeMixedOrdersGeometryAskLinearBid(1, 1, baseAmt, askPrice0, askRatio, bidPrice0, bidGap, 10000);

        uint64 grid2AskId = toGridOrderId(2, 0x8000);

        vm.startPrank(taker);
        exchange.fillAskOrder(grid2AskId, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.GridConfig memory grid2Conf = exchange.getGridConfig(2);
        // Higher fee should result in higher profits
        assertTrue(grid2Conf.profits > gridConf.profits);
    }
}
