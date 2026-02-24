// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {Geometry} from "../src/strategy/Geometry.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {Lens} from "../src/libraries/Lens.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {GridExBaseTest} from "./GridExBase.t.sol";

contract GridExFillGeometryTest is GridExBaseTest {
    Geometry public geometry;
    uint256 internal constant RATIO_MULTIPLIER = 1e18;

    function setUp() public override {
        super.setUp();
        geometry = new Geometry(address(exchange));
        AdminFacet(address(exchange)).setStrategyWhitelist(address(geometry), true);
    }

    function _placeGeometryOrders(
        uint32 askCount,
        uint32 bidCount,
        uint128 baseAmt,
        uint256 askPrice0,
        uint256 bidPrice0,
        uint256 askRatio,
        uint256 bidRatio
    ) internal {
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: geometry,
            bidStrategy: geometry,
            askData: abi.encode(askPrice0, askRatio),
            bidData: abi.encode(bidPrice0, bidRatio),
            askOrderCount: askCount,
            bidOrderCount: bidCount,
            baseAmount: baseAmt,
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        TradeFacet(address(exchange)).placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    function test_fillAskOrder_geometry() public {
        uint128 baseAmt = 10_000 ether;
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 askRatio = (11 * RATIO_MULTIPLIER) / 10; // 1.1

        _placeGeometryOrders(4, 0, baseAmt, askPrice0, 0, askRatio, 0);

        uint128 orderId0 = 0x80000000000000000000000000000001;
        uint128 orderId1 = orderId0 + 1;
        uint256 gridOrderId0 = toGridOrderId(1, orderId0);
        uint256 gridOrderId1 = toGridOrderId(1, orderId1);

        IGridOrder.OrderInfo memory order0Before = exchange.getGridOrder(gridOrderId0);
        IGridOrder.OrderInfo memory order1Before = exchange.getGridOrder(gridOrderId1);
        assertEq(order1Before.price, (order0Before.price * askRatio) / RATIO_MULTIPLIER);

        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId0, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.OrderInfo memory order0After = exchange.getGridOrder(gridOrderId0);
        assertEq(order0After.amount, 0);
        assertEq(order0After.revAmount, Lens.calcQuoteAmount(baseAmt, order0Before.revPrice, false));
    }

    function test_fillBidOrder_geometry() public {
        uint128 baseAmt = 10_000 ether;
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 bidRatio = (9 * RATIO_MULTIPLIER) / 10; // 0.9

        _placeGeometryOrders(0, 4, baseAmt, 0, bidPrice0, 0, bidRatio);

        uint128 orderId0 = 1;
        uint256 gridOrderId0 = toGridOrderId(1, orderId0);
        IGridOrder.OrderInfo memory order0Before = exchange.getGridOrder(gridOrderId0);

        vm.startPrank(taker);
        exchange.fillBidOrder(gridOrderId0, baseAmt, baseAmt, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.OrderInfo memory order0After = exchange.getGridOrder(gridOrderId0);
        assertEq(order0After.amount, 0);
        assertEq(order0After.revAmount, baseAmt);
        assertEq(order0Before.price, bidPrice0);
    }

    function test_fillAskOrders_geometryBatchWithMaxAmt() public {
        uint128 baseAmt = 5_000 ether;
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 askRatio = (105 * RATIO_MULTIPLIER) / 100; // 1.05

        _placeGeometryOrders(3, 0, baseAmt, askPrice0, 0, askRatio, 0);

        uint128 orderId0 = 0x80000000000000000000000000000001;
        uint256[] memory ids = new uint256[](3);
        ids[0] = toGridOrderId(1, orderId0);
        ids[1] = toGridOrderId(1, orderId0 + 1);
        ids[2] = toGridOrderId(1, orderId0 + 2);

        uint128[] memory amts = new uint128[](3);
        amts[0] = baseAmt;
        amts[1] = baseAmt;
        amts[2] = baseAmt;

        uint128 maxFill = baseAmt + (baseAmt / 2); // 1.5 orders
        vm.startPrank(taker);
        exchange.fillAskOrders(1, ids, amts, maxFill, 0, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.OrderInfo memory order0 = exchange.getGridOrder(ids[0]);
        IGridOrder.OrderInfo memory order1 = exchange.getGridOrder(ids[1]);
        IGridOrder.OrderInfo memory order2 = exchange.getGridOrder(ids[2]);

        assertEq(order0.amount, 0);
        assertEq(order1.amount, baseAmt - (maxFill - baseAmt));
        assertEq(order2.amount, baseAmt);
    }
}
