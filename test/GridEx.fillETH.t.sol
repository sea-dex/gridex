// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IWETH} from "../src/interfaces/IWETH.sol";
import {IPair} from "../src/interfaces/IPair.sol";
import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {IGridEx} from "../src/interfaces/IGridEx.sol";
import {IOrderEvents} from "../src/interfaces/IOrderEvents.sol";

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {GridEx} from "../src/GridEx.sol";
import {GridOrder} from "../src/GridOrder.sol";
import {Currency, CurrencyLibrary} from "../src/libraries/Currency.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

import {GridExBaseTest} from "./GridExBase.t.sol";

contract GridExFillETHTest is GridExBaseTest {
    Currency eth = Currency.wrap(address(0));

    function test_fillETHAskOrder() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        // uint96 orderId = 0x800000000000000000000001;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 2 ether / 100; // SEA

        _placeOrders(
            address(0),
            address(usdc),
            amt,
            10,
            0,
            askPrice0,
            0,
            gap,
            false,
            500
        );

        assertEq(amt * 10, weth.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(initialETHAmt - 10 * amt, eth.balanceOf(maker));

        uint256 gridOrderId = toGridOrderId(1, orderId);
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, amt, new bytes(0), 2);
        vm.stopPrank();

        // grid order flipped
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(0, order.amount);
        assertEq((amt * (askPrice0 - gap)) / PRICE_MULTIPLIER, order.revAmount);
        // eth balance
        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(initialETHAmt + amt, eth.balanceOf(taker));
        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) +
                eth.balanceOf(taker) +
                weth.balanceOf(address(exchange))
        );
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );

        // usdc balance
        (uint128 usdcVol, uint128 fees) = exchange.calcAskOrderQuoteAmount(
            askPrice0,
            amt,
            500
        );
        assertEq(initialUSDCAmt - usdcVol - fees, usdc.balanceOf(taker));
        assertEq(usdcVol + fees, usdc.balanceOf(address(exchange)));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            fees >> 1
        );

        // grid profit
        assertEq(
            gridConf.profits,
            fees - (fees >> 1) + (amt * gap) / PRICE_MULTIPLIER
        );

        // fill reversed order
        vm.startPrank(taker);
        weth.deposit{value: amt}();
        exchange.fillBidOrder(gridOrderId, amt, amt, new bytes(0), 0);
        vm.stopPrank();

        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );
        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) +
                eth.balanceOf(taker) +
                weth.balanceOf(address(exchange))
        );
        order = exchange.getGridOrder(gridOrderId);
        assertEq(amt, order.amount);
        assertEq(0, order.revAmount);

        (uint128 usdcVol2, uint128 fees2) = exchange.calcBidOrderQuoteAmount(
            askPrice0 - gap,
            amt,
            500
        );
        gridConf = exchange.getGridConfig(1);
        // grid profit
        assertEq(
            gridConf.profits,
            fees -
                (fees >> 1) +
                (amt * gap) /
                PRICE_MULTIPLIER +
                fees2 -
                (fees2 >> 1)
        );
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            (fees >> 1) + (fees2 >> 1)
        );

        // taker balance
        assertEq(
            initialUSDCAmt - usdcVol - fees + usdcVol2 - fees2,
            usdc.balanceOf(taker)
        );
        assertEq(initialETHAmt, eth.balanceOf(taker));
    }

    function test_partialFillETHAskOrder() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        // uint96 orderId = 0x800000000000000000000001;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 2 ether / 100; // ETH

        _placeOrders(
            address(0),
            address(usdc),
            amt,
            10,
            0,
            askPrice0,
            0,
            gap,
            false,
            500
        );

        assertEq(amt * 10, weth.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));

        uint128 fillAmt1 = 1 ether / 100;
        uint256 gridOrderId = toGridOrderId(1, orderId);
        for (uint i = 0; i < amt / fillAmt1; i++) {
            vm.startPrank(taker);
            exchange.fillAskOrder(gridOrderId, fillAmt1, fillAmt1, new bytes(0), 2);
            vm.stopPrank();

            assertEq(
                initialETHAmt * 2,
                eth.balanceOf(maker) +
                    eth.balanceOf(taker) +
                    weth.balanceOf(address(exchange))
            );
            assertEq(
                initialUSDCAmt * 2,
                usdc.balanceOf(maker) +
                    usdc.balanceOf(taker) +
                    usdc.balanceOf(address(exchange))
            );
        }

        // grid order flipped
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(0, order.amount);
        assertEq((amt * (askPrice0 - gap)) / PRICE_MULTIPLIER, order.revAmount);
        // sea balance
        assertEq(initialETHAmt + amt, eth.balanceOf(taker));
        assertEq(initialETHAmt - 10 * amt, eth.balanceOf(maker));

        // usdc balance
        (uint128 usdcVol, uint128 fees) = exchange.calcAskOrderQuoteAmount(
            askPrice0,
            amt,
            500
        );
        assertEq(initialUSDCAmt - usdcVol - fees, usdc.balanceOf(taker));
        assertEq(usdcVol + fees, usdc.balanceOf(address(exchange)));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            fees >> 1
        );

        // grid profit
        assertEq(
            gridConf.profits,
            fees - (fees >> 1) + (amt * gap) / PRICE_MULTIPLIER
        );
    }

    // fill multiple ask orders
    function test_partialFillETHAskOrders() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        // uint96 orderId = 0x800000000000000000000001;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 2 ether / 100; // SEA

        _placeOrders(
            address(0),
            address(usdc),
            amt,
            10,
            0,
            askPrice0,
            0,
            gap,
            false,
            500
        );

        assertEq(amt * 10, weth.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));

        vm.startPrank(taker);

        uint256[] memory orderIds = new uint256[](3);
        orderIds[0] = toGridOrderId(1, orderId);
        orderIds[1] = toGridOrderId(1, orderId + 1);
        orderIds[2] = toGridOrderId(1, orderId + 2);
        uint128[] memory amts = new uint128[](3);
        amts[0] = 7835448663132175;
        amts[1] = 5464897156364648;
        amts[2] = 7897856465416784;
        exchange.fillAskOrders(1, orderIds, amts, amt, 0, new bytes(0), 2);
        vm.stopPrank();

        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) +
                eth.balanceOf(taker) +
                weth.balanceOf(address(exchange))
        );
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );
        // grid order flipped
        IGridOrder.OrderInfo memory order0 = exchange.getGridOrder(orderIds[0]);
        IGridOrder.OrderInfo memory order1 = exchange.getGridOrder(orderIds[1]);
        IGridOrder.OrderInfo memory order2 = exchange.getGridOrder(orderIds[2]);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(amt - amts[0], order0.amount);
        assertEq(amt - amts[1], order1.amount);
        uint128 amtFilled3 = (amts[2] + amts[0] + amts[1]) > amt
            ? (amt - amts[0] - amts[1])
            : amts[2];
        assertEq(amt - amtFilled3, order2.amount);
        uint160 price0 = askPrice0;
        uint160 price1 = askPrice0 + gap;
        uint160 price2 = askPrice0 + gap * 2;
        (
            uint128 vol0,
            uint128 revVol0,
            uint128 profit0,
            uint128 fee0
        ) = calcQuoteVolReversed(price0, gap, amts[0], amt, 0, 500);
        (
            uint128 vol1,
            uint128 revVol1,
            uint128 profit1,
            uint128 fee1
        ) = calcQuoteVolReversed(price1, gap, amts[1], amt, 0, 500);
        (
            uint128 vol2,
            uint128 revVol2,
            uint128 profit2,
            uint128 fee2
        ) = calcQuoteVolReversed(price2, gap, amtFilled3, amt, 0, 500);
        // uint128 fillVol1 = calcQuoteVolReversed(amts[1], price1, true);
        // uint128 fillVol2 = calcQuoteVolReversed(amtFilled3, price2, true);
        assertEq(revVol0, order0.revAmount);
        assertEq(revVol1, order1.revAmount);
        assertEq(revVol2, order2.revAmount);
        assertEq(profit0, 0);
        assertEq(profit1, 0);
        assertEq(gridConf.profits, profit2);
        // eth balance
        assertEq(initialETHAmt + amt, eth.balanceOf(taker));
        assertEq(initialETHAmt - 10 * amt, eth.balanceOf(maker));

        uint128 fees = fee0 + fee1 + fee2;
        assertEq(
            initialUSDCAmt - vol0 - vol1 - vol2 - fees,
            usdc.balanceOf(taker)
        );
        assertEq(vol0 + vol1 + vol2 + fees, usdc.balanceOf(address(exchange)));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            (fee0 >> 1) + (fee1 >> 1) + (fee2 >> 1)
        );

        // grid profit
        assertEq(
            gridConf.profits,
            profit2
            // fees - (fees >> 1) + (amt * gap) / PRICE_MULTIPLIER
        );
    }

    function test_fillETHBidOrder() public {
        uint160 bidPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = bidPrice0 / 20; // 0.0001
        uint128 orderId = 0x000000000000000000000001;
        uint128 amt = 2 ether / 100; // ETH

        _placeOrders(
            address(0),
            address(usdc),
            amt,
            0,
            10,
            0,
            bidPrice0,
            gap,
            false,
            500
        );

        (, uint128 quoteAmt) = exchange.calcGridAmount(
            amt,
            bidPrice0,
            gap,
            0,
            10
        );

        assertEq(0, weth.balanceOf(address(exchange)));
        assertEq(quoteAmt, usdc.balanceOf(address(exchange)));

        uint256 gridOrderId = toGridOrderId(1, orderId);
        vm.startPrank(taker);
        exchange.fillBidOrder{value: amt}(gridOrderId, amt, amt, new bytes(0), 1);
        vm.stopPrank();

        // grid order flipped
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(0, order.amount);
        assertEq(amt, order.revAmount);
        // sea balance
        assertEq(initialETHAmt - amt, eth.balanceOf(taker));
        assertEq(initialETHAmt, eth.balanceOf(maker));
        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) +
                eth.balanceOf(taker) +
                weth.balanceOf(address(exchange))
        );
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );

        // usdc balance
        (uint128 usdcVol, uint128 fees) = exchange.calcBidOrderQuoteAmount(
            bidPrice0,
            amt,
            500
        );
        assertEq(initialUSDCAmt + usdcVol - fees, usdc.balanceOf(taker));
        assertEq(initialUSDCAmt - quoteAmt, usdc.balanceOf(maker));
        assertEq(quoteAmt - usdcVol + fees, usdc.balanceOf(address(exchange)));
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            fees >> 1
        );

        // grid profit
        assertEq(gridConf.profits, fees - (fees >> 1));

        // fill reversed order
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, amt, new bytes(0), 0);
        vm.stopPrank();

        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );
        assertEq(amt, weth.balanceOf(taker));
        assertEq(
            initialETHAmt * 2 - amt,
            eth.balanceOf(maker) +
                eth.balanceOf(taker) +
                weth.balanceOf(address(exchange))
        );
        order = exchange.getGridOrder(gridOrderId);
        assertEq((amt * bidPrice0) / PRICE_MULTIPLIER, order.amount);
        assertEq(0, order.revAmount);

        // maker balance not change
        assertEq(initialETHAmt, eth.balanceOf(maker));
        assertEq(initialUSDCAmt - quoteAmt, usdc.balanceOf(maker));

        (uint128 usdcVol2, uint128 fees2) = exchange.calcAskOrderQuoteAmount(
            bidPrice0 + gap,
            amt,
            500
        );
        gridConf = exchange.getGridConfig(1);
        // grid profit
        assertEq(
            gridConf.profits,
            fees -
                (fees >> 1) +
                (amt * gap) /
                PRICE_MULTIPLIER +
                fees2 -
                (fees2 >> 1)
        );
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            (fees >> 1) + (fees2 >> 1)
        );

        // taker balance
        assertEq(
            initialUSDCAmt + usdcVol - fees - usdcVol2 - fees2,
            usdc.balanceOf(taker)
        );
        assertEq(initialETHAmt - amt, eth.balanceOf(taker));
        assertEq(amt, weth.balanceOf(taker));
    }

    function test_partialFillETHBidOrders1() public {
        uint160 bidPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = bidPrice0 / 20; // 0.0001
        uint128 orderId = 0x000000000000000000000001;
        uint128 amt = 2 ether / 100; // ETH

        _placeOrders(
            address(0),
            address(usdc),
            amt,
            0,
            10,
            0,
            bidPrice0,
            gap,
            false,
            500
        );

        (, uint128 totalQuoteAmt) = exchange.calcGridAmount(
            amt,
            bidPrice0,
            gap,
            0,
            10
        );
        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(0, weth.balanceOf(address(exchange)));
        assertEq(totalQuoteAmt, usdc.balanceOf(address(exchange)));
        uint160 price0 = bidPrice0;
        uint160 price1 = bidPrice0 - gap;
        uint160 price2 = bidPrice0 - gap * 2;

        uint128 quoteAmt0 = exchange.calcQuoteAmount(amt, price0, false);
        uint128 quoteAmt1 = exchange.calcQuoteAmount(amt, price1, false);
        uint128 quoteAmt2 = exchange.calcQuoteAmount(amt, price2, false);
        uint256[] memory orderIds = new uint256[](3);
        orderIds[0] = toGridOrderId(1, orderId);
        orderIds[1] = toGridOrderId(1, orderId + 1);
        orderIds[2] = toGridOrderId(1, orderId + 2);
        IGridOrder.OrderInfo memory order0 = exchange.getGridOrder(orderIds[0]);
        IGridOrder.OrderInfo memory order1 = exchange.getGridOrder(orderIds[1]);
        IGridOrder.OrderInfo memory order2 = exchange.getGridOrder(orderIds[2]);
        assertEq(order0.amount, quoteAmt0);
        assertEq(order1.amount, quoteAmt1);
        assertEq(order2.amount, quoteAmt2);

        uint128[] memory amts = new uint128[](3);
        amts[0] = 8497464616475387;
        amts[1] = 7465161434874343;
        amts[2] = 6426489715636468;

        vm.startPrank(taker);
        exchange.fillBidOrders{value: amt * 2}(
            1,
            orderIds,
            amts,
            amt + amt / 2,
            0,
            new bytes(0),
            1
        );
        vm.stopPrank();

        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) +
                eth.balanceOf(taker) +
                weth.balanceOf(address(exchange))
        );
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );
        // grid order flipped
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        order0 = exchange.getGridOrder(orderIds[0]);
        order1 = exchange.getGridOrder(orderIds[1]);
        order2 = exchange.getGridOrder(orderIds[2]);

        (uint128 fillVol0, uint128 fee0) = exchange.calcBidOrderQuoteAmount(
            price0,
            amts[0],
            500
        );
        (uint128 fillVol1, uint128 fee1) = exchange.calcBidOrderQuoteAmount(
            price1,
            amts[1],
            500
        );
        (uint128 fillVol2, uint128 fee2) = exchange.calcBidOrderQuoteAmount(
            price2,
            amts[2],
            500
        );

        assertEq(quoteAmt0 - fillVol0, order0.amount);
        assertEq(quoteAmt1 - fillVol1, order1.amount);
        assertEq(quoteAmt2 - fillVol2, order2.amount);
        // uint128 fillVol1 = calcQuoteVolReversed(amts[1], price1, true);
        // uint128 fillVol2 = calcQuoteVolReversed(amtFilled3, price2, true);
        assertEq(amts[0], order0.revAmount);
        assertEq(amts[1], order1.revAmount);
        assertEq(amts[2], order2.revAmount);

        // grid profits
        uint128 protocolFee = (fee0 >> 1) + (fee1 >> 1) + (fee2 >> 1);
        // protocol profits
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            protocolFee
        );
        assertEq(gridConf.profits, fee0 + fee1 + fee2 - protocolFee);

        // taker balance
        assertEq(
            initialETHAmt - amts[0] - amts[1] - amts[2],
            eth.balanceOf(taker)
        );
        assertEq(
            initialUSDCAmt +
                fillVol0 -
                fee0 +
                fillVol1 -
                fee1 +
                fillVol2 -
                fee2,
            usdc.balanceOf(taker)
        );

        // maker balance
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt - totalQuoteAmt, usdc.balanceOf(maker));
    }

    function test_partialFillETHBidOrders2() public {
        uint160 bidPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = bidPrice0 / 20; // 0.0001
        uint128 orderId = 0x000000000000000000000001;
        uint128 amt = 2 ether / 100; // ETH

        _placeOrders(
            address(0),
            address(usdc),
            amt,
            0,
            10,
            0,
            bidPrice0,
            gap,
            false,
            500
        );

        (, uint128 totalQuoteAmt) = exchange.calcGridAmount(
            amt,
            bidPrice0,
            gap,
            0,
            10
        );
        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(0, weth.balanceOf(address(exchange)));
        assertEq(totalQuoteAmt, usdc.balanceOf(address(exchange)));
        uint160 price0 = bidPrice0;
        uint160 price1 = bidPrice0 - gap;
        uint160 price2 = bidPrice0 - gap * 2;

        uint128 quoteAmt0 = exchange.calcQuoteAmount(amt, price0, false);
        uint128 quoteAmt1 = exchange.calcQuoteAmount(amt, price1, false);
        uint128 quoteAmt2 = exchange.calcQuoteAmount(amt, price2, false);
        uint256[] memory orderIds = new uint256[](3);
        orderIds[0] = toGridOrderId(1, orderId);
        orderIds[1] = toGridOrderId(1, orderId + 1);
        orderIds[2] = toGridOrderId(1, orderId + 2);
        IGridOrder.OrderInfo memory order0 = exchange.getGridOrder(orderIds[0]);
        IGridOrder.OrderInfo memory order1 = exchange.getGridOrder(orderIds[1]);
        IGridOrder.OrderInfo memory order2 = exchange.getGridOrder(orderIds[2]);
        assertEq(order0.amount, quoteAmt0);
        assertEq(order1.amount, quoteAmt1);
        assertEq(order2.amount, quoteAmt2);

        uint128[] memory amts = new uint128[](3);
        amts[0] = 8497464616475387;
        amts[1] = 7465161434874343;
        amts[2] = 6426489715636468;

        vm.startPrank(taker);
        weth.deposit{value: amt * 2}();
        exchange.fillBidOrders(1, orderIds, amts, amt + amt / 2, 0, new bytes(0), 0);
        vm.stopPrank();

        assertEq(amt * 2 - amts[0] - amts[1] - amts[2], weth.balanceOf(taker));
        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) +
                eth.balanceOf(taker) +
                weth.balanceOf(taker) +
                weth.balanceOf(address(exchange))
        );
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );
        // grid order flipped
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        order0 = exchange.getGridOrder(orderIds[0]);
        order1 = exchange.getGridOrder(orderIds[1]);
        order2 = exchange.getGridOrder(orderIds[2]);

        (uint128 fillVol0, uint128 fee0) = exchange.calcBidOrderQuoteAmount(
            price0,
            amts[0],
            500
        );
        (uint128 fillVol1, uint128 fee1) = exchange.calcBidOrderQuoteAmount(
            price1,
            amts[1],
            500
        );
        (uint128 fillVol2, uint128 fee2) = exchange.calcBidOrderQuoteAmount(
            price2,
            amts[2],
            500
        );

        assertEq(quoteAmt0 - fillVol0, order0.amount);
        assertEq(quoteAmt1 - fillVol1, order1.amount);
        assertEq(quoteAmt2 - fillVol2, order2.amount);
        // uint128 fillVol1 = calcQuoteVolReversed(amts[1], price1, true);
        // uint128 fillVol2 = calcQuoteVolReversed(amtFilled3, price2, true);
        assertEq(amts[0], order0.revAmount);
        assertEq(amts[1], order1.revAmount);
        assertEq(amts[2], order2.revAmount);

        // grid profits
        uint128 protocolFee = (fee0 >> 1) + (fee1 >> 1) + (fee2 >> 1);
        // protocol profits
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            protocolFee
        );
        assertEq(gridConf.profits, fee0 + fee1 + fee2 - protocolFee);

        // taker balance
        assertEq(
            initialETHAmt - amts[0] - amts[1] - amts[2],
            eth.balanceOf(taker) + weth.balanceOf(taker)
        );
        assertEq(
            initialUSDCAmt +
                fillVol0 -
                fee0 +
                fillVol1 -
                fee1 +
                fillVol2 -
                fee2,
            usdc.balanceOf(taker)
        );

        // maker balance
        assertEq(initialETHAmt, eth.balanceOf(maker));
        assertEq(initialUSDCAmt - totalQuoteAmt, usdc.balanceOf(maker));
    }
}
