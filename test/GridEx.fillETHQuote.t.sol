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

contract GridExFillETHQuoteTest is GridExBaseTest {
    Currency eth = Currency.wrap(address(0));

    function test_fillETHQuoteAskOrder() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 20 ether; // SEA

        _placeOrders(
            address(sea),
            address(0),
            amt,
            10,
            0,
            askPrice0,
            0,
            gap,
            false,
            500
        );

        assertEq(amt * 10, sea.balanceOf(address(exchange)));
        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(0, weth.balanceOf(address(exchange)));
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        assertEq(gridConf.startAskOrderId, orderId);
        assertEq(gridConf.askOrderCount, 10);

        (uint128 ethVol, uint128 fee) = exchange.calcAskOrderQuoteAmount(
            askPrice0,
            amt,
            500
        );
        uint256 gridOrderId = toGridOrderId(1, orderId);
        assertEq(gridOrderId, 0x180000000000000000000000000000001);

        vm.startPrank(taker);
        exchange.fillAskOrder{value: ethVol + fee}(gridOrderId, amt, amt, 1); // intoken: ETH
        vm.stopPrank();

        // grid order flipped
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        gridConf = exchange.getGridConfig(1);

        assertEq(0, order.amount);
        assertEq((amt * (askPrice0 - gap)) / PRICE_MULTIPLIER, order.revAmount);
        // eth balance
        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(
            fee - fee / 2 + (amt * gap) / PRICE_MULTIPLIER,
            gridConf.profits
        );
        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) +
                eth.balanceOf(taker) +
                weth.balanceOf(address(exchange))
        );
        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
        );
        assertEq(initialETHAmt, eth.balanceOf(maker));
        assertEq(ethVol + fee, weth.balanceOf(address(exchange)));
        assertEq(initialETHAmt - ethVol - fee, eth.balanceOf(taker));

        assertEq(exchange.protocolFees(Currency.wrap(address(weth))), fee >> 1);

        // grid profit
        assertEq(
            gridConf.profits,
            fee - (fee >> 1) + (amt * gap) / PRICE_MULTIPLIER
        );

        // fill reversed order
        vm.startPrank(taker);
        // weth.deposit{value: amt}();
        exchange.fillBidOrder(gridOrderId, amt, amt, 0);
        vm.stopPrank();

        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
        );
        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) +
                eth.balanceOf(taker) +
                weth.balanceOf(taker) +
                weth.balanceOf(address(exchange))
        );
        order = exchange.getGridOrder(gridOrderId);
        assertEq(amt, order.amount);
        assertEq(0, order.revAmount);

        (uint128 ethVol2, uint128 fees2) = exchange.calcBidOrderQuoteAmount(
            askPrice0 - gap,
            amt,
            500
        );
        gridConf = exchange.getGridConfig(1);
        // grid profit
        assertEq(
            gridConf.profits,
            fee -
                (fee >> 1) +
                (amt * gap) /
                PRICE_MULTIPLIER +
                fees2 -
                (fees2 >> 1)
        );
        assertEq(
            exchange.protocolFees(Currency.wrap(address(weth))),
            (fee >> 1) + (fees2 >> 1)
        );

        // taker balance
        assertEq(
            initialETHAmt - ethVol - fee + ethVol2 - fees2,
            eth.balanceOf(taker) + weth.balanceOf(taker)
        );
        assertEq(initialSEAAmt, sea.balanceOf(taker));
    }

    // fill multiple ask orders
    function test_partialFillETHQuoteAskOrders() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 20 ether; // SEA

        _placeOrders(
            address(sea),
            address(0),
            amt,
            10,
            0,
            askPrice0,
            0,
            gap,
            false,
            500
        );

        assertEq(amt * 10, sea.balanceOf(address(exchange)));
        assertEq(0, weth.balanceOf(address(exchange)));
        assertEq(0, eth.balanceOf(address(exchange)));

        uint256[] memory orderIds = new uint256[](3);
        orderIds[0] = toGridOrderId(1, orderId);
        orderIds[1] = toGridOrderId(1, orderId + 1);
        orderIds[2] = toGridOrderId(1, orderId + 2);
        uint128[] memory amts = new uint128[](3);
        amts[0] = amt;
        amts[1] = amt;
        amts[2] = amt / 4;

        (uint128 ethVol0, uint128 fee0) = exchange.calcAskOrderQuoteAmount(
            askPrice0,
            amt,
            500
        );
        (uint128 ethVol1, uint128 fee1) = exchange.calcAskOrderQuoteAmount(
            askPrice0 + gap,
            amt,
            500
        );
        (uint128 ethVol2, uint128 fee2) = exchange.calcAskOrderQuoteAmount(
            askPrice0 + gap * 2,
            amt / 4,
            500
        );
        uint128 ethVolTotal = ethVol0 + ethVol1 + ethVol2;
        uint128 feeTotal = fee0 + fee1 + fee2;

        vm.startPrank(taker);
        exchange.fillAskOrders{value: ethVolTotal + feeTotal}(
            1,
            orderIds,
            amts,
            amt * 3,
            0,
            1
        ); // inToken: ETH
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
        IGridOrder.OrderInfo memory order0 = exchange.getGridOrder(
            toGridOrderId(1, orderId)
        );
        IGridOrder.OrderInfo memory order1 = exchange.getGridOrder(
            toGridOrderId(1, orderId + 1)
        );
        IGridOrder.OrderInfo memory order2 = exchange.getGridOrder(
            toGridOrderId(1, orderId + 2)
        );
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(amt - amts[0], order0.amount);
        assertEq(amt - amts[1], order1.amount);
        uint128 amtFilled3 = amts[2];
        assertEq(amt - amtFilled3, order2.amount);
        uint160 price0 = askPrice0;
        uint160 price1 = askPrice0 + gap;
        uint160 price2 = askPrice0 + gap * 2;
        (
            uint128 vol0,
            uint128 revVol0,
            uint128 profit0,

        ) = calcQuoteVolReversed(price0, gap, amts[0], amt, 0, 500);
        (
            uint128 vol1,
            uint128 revVol1,
            uint128 profit1,

        ) = calcQuoteVolReversed(price1, gap, amts[1], amt, 0, 500);
        (
            uint128 vol2,
            uint128 revVol2,
            uint128 profit2,

        ) = calcQuoteVolReversed(price2, gap, amtFilled3, amt, 0, 500);
        // uint128 fillVol1 = calcQuoteVolReversed(amts[1], price1, true);
        // uint128 fillVol2 = calcQuoteVolReversed(amtFilled3, price2, true);
        assertEq(revVol0, order0.revAmount);
        assertEq(revVol1, order1.revAmount);
        assertEq(revVol2, order2.revAmount);
        // assertEq(profit0, 0);
        // assertEq(profit1, 0);
        assertEq(gridConf.profits, profit0 + profit1 + profit2);
        // eth balance
        assertEq(initialETHAmt, eth.balanceOf(maker));
        assertEq(initialETHAmt - ethVolTotal - feeTotal, eth.balanceOf(taker));

        uint128 fees = fee0 + fee1 + fee2;
        assertEq(feeTotal, fees);
        assertEq(
            initialETHAmt - vol0 - vol1 - vol2 - fees,
            eth.balanceOf(taker)
        );
        assertEq(vol0 + vol1 + vol2 + fees, weth.balanceOf(address(exchange)));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));
        assertEq(
            exchange.protocolFees(Currency.wrap(address(weth))),
            (fee0 >> 1) + (fee1 >> 1) + (fee2 >> 1)
        );
    }

    function test_fillETHQuoteBidOrder() public {
        uint160 bidPrice0 = uint160(PRICE_MULTIPLIER / 500); // 0.002
        uint160 gap = bidPrice0 / 20; // 0.0001
        uint128 orderId = 0x000000000000000000000001;
        uint128 amt = 200 ether; // ETH

        _placeOrders(
            address(sea),
            address(0),
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

        assertEq(quoteAmt, weth.balanceOf(address(exchange)));
        assertEq(0, sea.balanceOf(address(exchange)));
        uint256 gridOrderId = toGridOrderId(1, orderId);
        // grid order flipped
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        // console.log(order.amount);
        // console.log(order.revAmount);

        vm.startPrank(taker);
        exchange.fillBidOrder(gridOrderId, amt, amt, 2); // outToken: ETH
        vm.stopPrank();

        // grid order flipped
        order = exchange.getGridOrder(gridOrderId);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        // console.log(gridConf.startBidOrderId);

        assertEq(amt, order.revAmount);
        assertEq(0, order.amount);
        // sea balance
        assertEq(initialSEAAmt - amt, sea.balanceOf(taker));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) +
                eth.balanceOf(taker) +
                weth.balanceOf(address(exchange))
        );
        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
        );

        // eth balance
        (uint128 ethVol, uint128 fees) = exchange.calcBidOrderQuoteAmount(
            bidPrice0,
            amt,
            500
        );
        assertEq(initialETHAmt + ethVol - fees, eth.balanceOf(taker));
        assertEq(initialETHAmt - quoteAmt, eth.balanceOf(maker));
        assertEq(quoteAmt - ethVol + fees, weth.balanceOf(address(exchange)));
        assertEq(
            exchange.protocolFees(Currency.wrap(address(weth))),
            fees >> 1
        );

        // grid profit
        assertEq(gridConf.profits, fees - (fees >> 1));

        (uint128 ethVol2, uint128 fees2) = exchange.calcAskOrderQuoteAmount(
            bidPrice0 + gap,
            amt,
            500
        );
        // fill reversed order
        vm.startPrank(taker);
        exchange.fillAskOrder{value: ethVol2 + fees2}(gridOrderId, amt, amt, 1); // inToken: ETH
        vm.stopPrank();

        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
        );
        assertEq(initialSEAAmt, sea.balanceOf(taker));
        assertEq(
            initialETHAmt - ethVol2 - fees2 + ethVol - fees,
            eth.balanceOf(taker)
        );
        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) +
                eth.balanceOf(taker) +
                weth.balanceOf(address(exchange))
        );
        order = exchange.getGridOrder(gridOrderId);
        assertEq((amt * bidPrice0) / PRICE_MULTIPLIER, order.amount);
        assertEq(0, order.revAmount);

        // maker balance not change
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialETHAmt - quoteAmt, eth.balanceOf(maker));

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
            exchange.protocolFees(Currency.wrap(address(weth))),
            (fees >> 1) + (fees2 >> 1)
        );

        // taker balance
        assertEq(
            initialETHAmt + ethVol - fees - ethVol2 - fees2,
            eth.balanceOf(taker)
        );
        assertEq(initialSEAAmt, sea.balanceOf(taker));
    }

    function test_partialFillETHQuoteBidOrders() public {
        uint160 bidPrice0 = uint160(PRICE_MULTIPLIER / 500); // 0.002
        uint160 gap = bidPrice0 / 20; // 0.0001
        uint128 orderId = 0x000000000000000000000001;
        uint128 amt = 2 ether; // SEA

        _placeOrders(
            address(sea),
            address(0),
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
        assertEq(totalQuoteAmt, weth.balanceOf(address(exchange)));
        assertEq(0, sea.balanceOf(address(exchange)));
        uint160 price0 = bidPrice0;
        uint160 price1 = bidPrice0 - gap;
        uint160 price2 = bidPrice0 - gap * 2;

        uint128 quoteAmt0 = exchange.calcQuoteAmount(amt, price0, false);
        uint128 quoteAmt1 = exchange.calcQuoteAmount(amt, price1, false);
        uint128 quoteAmt2 = exchange.calcQuoteAmount(amt, price2, false);
        IGridOrder.OrderInfo memory order0 = exchange.getGridOrder(
            toGridOrderId(1, orderId)
        );
        IGridOrder.OrderInfo memory order1 = exchange.getGridOrder(
            toGridOrderId(1, orderId + 1)
        );
        IGridOrder.OrderInfo memory order2 = exchange.getGridOrder(
            toGridOrderId(1, orderId + 2)
        );
        assertEq(order0.amount, quoteAmt0);
        assertEq(order1.amount, quoteAmt1);
        assertEq(order2.amount, quoteAmt2);

        uint256[] memory orderIds = new uint256[](3);
        orderIds[0] = toGridOrderId(1, orderId);
        orderIds[1] = toGridOrderId(1, orderId + 1);
        orderIds[2] = toGridOrderId(1, orderId + 2);
        uint128[] memory amts = new uint128[](3);
        amts[0] = amt;
        amts[1] = amt;
        amts[2] = amt / 5;

        vm.startPrank(taker);
        exchange.fillBidOrders(1, orderIds, amts, amt * 2 + amt / 2, 0, 2); // outToken: ETH
        vm.stopPrank();

        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) +
                eth.balanceOf(taker) +
                weth.balanceOf(address(exchange))
        );
        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
        );
        // grid order flipped
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        order0 = exchange.getGridOrder(toGridOrderId(1, orderId));
        order1 = exchange.getGridOrder(toGridOrderId(1, orderId + 1));
        order2 = exchange.getGridOrder(toGridOrderId(1, orderId + 2));

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
            exchange.protocolFees(Currency.wrap(address(weth))),
            protocolFee
        );
        assertEq(gridConf.profits, fee0 + fee1 + fee2 - protocolFee);

        // taker balance
        assertEq(
            initialSEAAmt - amts[0] - amts[1] - amts[2],
            sea.balanceOf(taker)
        );
        assertEq(
            initialETHAmt + fillVol0 - fee0 + fillVol1 - fee1 + fillVol2 - fee2,
            eth.balanceOf(taker)
        );

        // maker balance
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialETHAmt - totalQuoteAmt, eth.balanceOf(maker));
    }
}
