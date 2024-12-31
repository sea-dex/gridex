// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IWETH} from "../src/interfaces/IWETH.sol";
import {IPair} from "../src/interfaces/IPair.sol";
import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {IGridEx} from "../src/interfaces/IGridEx.sol";
// import {IGridExCallback} from "../src/interfaces/IGridExCallback.sol";
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

contract GridExFillCompoundTest is GridExBaseTest {
    function test_fillCompoundAskOrder() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        uint96 orderId = 0x800000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(
            address(sea),
            address(usdc),
            amt,
            10,
            0,
            askPrice0,
            0,
            gap,
            true,
            500
        );

        assertEq(amt * 10, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));

        vm.startPrank(taker);
        exchange.fillAskOrder(orderId, amt, amt, 0);
        vm.stopPrank();

        // grid order flipped
        IGridOrder.Order memory order = exchange.getGridOrder(orderId);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(0, order.amount);
        // usdc balance
        (uint128 usdcVol, uint128 fees) = exchange.calcAskOrderQuoteAmount(
            askPrice0,
            amt,
            500
        );
        assertEq(usdcVol + makerFee(fees), order.revAmount);
        // sea balance
        assertEq(initialSEAAmt + amt, sea.balanceOf(taker));
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));
        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
        );
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );

        assertEq(initialUSDCAmt - usdcVol - fees, usdc.balanceOf(taker));
        assertEq(usdcVol + fees, usdc.balanceOf(address(exchange)));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            fees >> 1
        );

        // grid profit
        assertEq(gridConf.profits, 0);

        // fill reversed order
        vm.startPrank(taker);
        exchange.fillBidOrder(orderId, amt, amt, 0);
        vm.stopPrank();

        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );
        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
        );
        (uint128 usdcVol2, uint128 fees2) = exchange.calcBidOrderQuoteAmount(
            askPrice0 - gap,
            amt,
            500
        );
        order = exchange.getGridOrder(orderId);
        assertEq(amt, order.amount);
        assertEq(
            usdcVol + makerFee(fees) - usdcVol2 + makerFee(fees2),
            order.revAmount
        );

        gridConf = exchange.getGridConfig(1);
        // grid profit
        assertEq(gridConf.profits, 0);
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            (fees >> 1) + (fees2 >> 1)
        );

        // taker balance
        assertEq(
            initialUSDCAmt - usdcVol - fees + usdcVol2 - fees2,
            usdc.balanceOf(taker)
        );
        assertEq(initialSEAAmt, sea.balanceOf(taker));
    }

    function test_partialFillCompoundAskOrder() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        uint96 orderId = 0x800000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(
            address(sea),
            address(usdc),
            amt,
            10,
            0,
            askPrice0,
            0,
            gap,
            true,
            500
        );

        assertEq(amt * 10, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));

        uint128 fillAmt1 = 1000 ether;
        for (uint i = 0; i < amt / fillAmt1; i++) {
            vm.startPrank(taker);
            exchange.fillAskOrder(orderId, fillAmt1, fillAmt1, 0);
            vm.stopPrank();

            assertEq(
                initialSEAAmt * 2,
                sea.balanceOf(maker) +
                    sea.balanceOf(taker) +
                    sea.balanceOf(address(exchange))
            );
            assertEq(
                initialUSDCAmt * 2,
                usdc.balanceOf(maker) +
                    usdc.balanceOf(taker) +
                    usdc.balanceOf(address(exchange))
            );
        }

        // grid order flipped
        IGridOrder.Order memory order = exchange.getGridOrder(orderId);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(0, order.amount);
        uint128 vol = uint128((amt * askPrice0) / PRICE_MULTIPLIER);
        uint128 fee = (vol * 500) / 1000000;
        assertEq(vol + makerFee(fee), order.revAmount);
        // sea balance
        assertEq(initialSEAAmt + amt, sea.balanceOf(taker));
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));

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
        assertEq(gridConf.profits, 0);
    }

    // fill multiple ask orders
    function test_partialFillCompoundAskOrders() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        uint96 orderId = 0x800000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(
            address(sea),
            address(usdc),
            amt,
            10,
            0,
            askPrice0,
            0,
            gap,
            true,
            500
        );

        assertEq(amt * 10, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));

        vm.startPrank(taker);

        uint96[] memory orderIds = new uint96[](3);
        orderIds[0] = orderId;
        orderIds[1] = orderId + 1;
        orderIds[2] = orderId + 2;
        uint128[] memory amts = new uint128[](3);
        amts[0] = 10 ether + 783544866523132175;
        amts[1] = 200 ether + 54648971563646448;
        amts[2] = 20000 ether - 4897895643465416784;
        exchange.fillAskOrders(1, orderIds, amts, amt, 0, 0);
        vm.stopPrank();

        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
        );
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );
        // grid order flipped
        IGridOrder.Order memory order0 = exchange.getGridOrder(orderId);
        IGridOrder.Order memory order1 = exchange.getGridOrder(orderId + 1);
        IGridOrder.Order memory order2 = exchange.getGridOrder(orderId + 2);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(amt - amts[0], order0.amount);
        assertEq(amt - amts[1], order1.amount);
        uint128 amtFilled3 = amt - (amts[0]) - (amts[1]);
        assertEq(amt - amtFilled3, order2.amount);
        uint160 price0 = askPrice0;
        uint160 price1 = askPrice0 + gap;
        uint160 price2 = askPrice0 + gap * 2;
        (
            uint128 vol0,
            uint128 revVol0,
            uint128 fee0
        ) = calcQuoteVolReversedCompound(price0, amts[0], 500);
        (
            uint128 vol1,
            uint128 revVol1,
            uint128 fee1
        ) = calcQuoteVolReversedCompound(price1, amts[1], 500);
        (
            uint128 vol2,
            uint128 revVol2,
            uint128 fee2
        ) = calcQuoteVolReversedCompound(price2, amtFilled3, 500);
        // uint128 fillVol1 = calcQuoteVolReversed(amts[1], price1, true);
        // uint128 fillVol2 = calcQuoteVolReversed(amtFilled3, price2, true);
        assertEq(revVol0, order0.revAmount);
        assertEq(revVol1, order1.revAmount);
        assertEq(revVol2, order2.revAmount);

        // sea balance
        assertEq(initialSEAAmt + amt, sea.balanceOf(taker));
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));

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
        assertEq(gridConf.profits, 0);
    }

    function test_fillCompoundBidOrder() public {
        uint160 bidPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = bidPrice0 / 20; // 0.0001
        uint96 orderId = 0x000000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(
            address(sea),
            address(usdc),
            amt,
            0,
            10,
            0,
            bidPrice0,
            gap,
            true,
            500
        );

        uint128 quoteAmt = 0;
        uint160 price = bidPrice0;
        for (int i = 0; i < 10; i++) {
            quoteAmt += exchange.calcQuoteAmount(amt, price, false);
            price = price - gap;
        }

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(quoteAmt, usdc.balanceOf(address(exchange)));

        vm.startPrank(taker);
        exchange.fillBidOrder(orderId, amt, amt, 0);
        vm.stopPrank();

        // grid order flipped
        IGridOrder.Order memory order = exchange.getGridOrder(orderId);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        // sea balance
        assertEq(initialSEAAmt - amt, sea.balanceOf(taker));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
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
        assertEq(makerFee(fees), order.amount);
        assertEq(amt, order.revAmount);

        assertEq(initialUSDCAmt + usdcVol - fees, usdc.balanceOf(taker));
        assertEq(initialUSDCAmt - quoteAmt, usdc.balanceOf(maker));
        assertEq(quoteAmt - usdcVol + fees, usdc.balanceOf(address(exchange)));
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            fees >> 1
        );

        // grid profit
        assertEq(gridConf.profits, 0);

        // fill reversed order
        vm.startPrank(taker);
        exchange.fillAskOrder(orderId, amt, amt, 0);
        vm.stopPrank();

        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );
        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
        );
        (uint128 usdcVol2, uint128 fees2) = exchange.calcAskOrderQuoteAmount(
            bidPrice0 + gap,
            amt,
            500
        );
        order = exchange.getGridOrder(orderId);
        assertEq(makerFee(fees) + usdcVol2 + makerFee(fees2), order.amount);
        assertEq(0, order.revAmount);

        // maker balance not change
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt - quoteAmt, usdc.balanceOf(maker));

        gridConf = exchange.getGridConfig(1);
        // grid profit
        assertEq(gridConf.profits, 0);
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            (fees >> 1) + (fees2 >> 1)
        );

        // taker balance
        assertEq(
            initialUSDCAmt + usdcVol - fees - usdcVol2 - fees2,
            usdc.balanceOf(taker)
        );
        assertEq(initialSEAAmt, sea.balanceOf(taker));
    }

    function test_partialFillCompoundBidOrder() public {
        uint160 bidPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = bidPrice0 / 20; // 0.0001
        uint96 orderId = 0x000000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(
            address(sea),
            address(usdc),
            amt,
            0,
            10,
            0,
            bidPrice0,
            gap,
            true,
            500
        );

        // uint128 quoteAmt = 0;
        // uint160 price = bidPrice0;
        // for (int i = 0; i < 10; i++) {
        //     quoteAmt += exchange.calcQuoteAmount(amt, price, false);
        //     price = price - gap;
        // }
        (, uint128 totalQuoteAmt) = exchange.calcGridAmount(
            amt,
            bidPrice0,
            gap,
            0,
            10
        );

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(totalQuoteAmt, usdc.balanceOf(address(exchange)));
        IGridOrder.Order memory order0 = exchange.getGridOrder(orderId);
        assertEq(0, order0.revAmount);
        uint128 quoteAmt0 = exchange.calcQuoteAmount(amt, bidPrice0, false);
        assertEq(quoteAmt0, order0.amount);

        uint128 fillAmt = amt - 45455424988975486;
        vm.startPrank(taker);
        exchange.fillBidOrder(orderId, fillAmt, 0, 0);
        vm.stopPrank();

        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
        );
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );

        // grid order flipped
        order0 = exchange.getGridOrder(orderId);

        // usdc balance
        (uint128 usdcVol0, uint128 fees) = exchange.calcBidOrderQuoteAmount(
            bidPrice0,
            fillAmt,
            500
        );
        uint128 leftQuoteAmt = quoteAmt0 - usdcVol0 + makerFee(fees);
        assertEq(leftQuoteAmt, order0.amount);
        assertEq(fillAmt, order0.revAmount);
        // sea balance
        assertEq(initialSEAAmt - fillAmt, sea.balanceOf(taker));
        assertEq(initialSEAAmt, sea.balanceOf(maker));

        assertEq(initialUSDCAmt + usdcVol0 - fees, usdc.balanceOf(taker));
        assertEq(initialUSDCAmt - totalQuoteAmt, usdc.balanceOf(maker));
        assertEq(
            totalQuoteAmt - usdcVol0 + fees,
            usdc.balanceOf(address(exchange))
        );
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            fees >> 1
        );

        // grid profit
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        assertEq(gridConf.profits, 0);

        // fill reversed order
        uint128 fillAmt1 = fillAmt - 4156489783946137867;
        vm.startPrank(taker);
        exchange.fillAskOrder(orderId, fillAmt1, 0, 0);
        vm.stopPrank();

        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );
        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
        );
        // maker balance not change
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt - totalQuoteAmt, usdc.balanceOf(maker));

        (uint128 usdcVol1, uint128 fees1) = exchange.calcAskOrderQuoteAmount(
            bidPrice0 + gap,
            fillAmt1,
            500
        );
        (
            uint128 fillVol,
            uint128 orderQuoteAmt,
            uint128 fee
        ) = calcQuoteVolReversedCompound(bidPrice0 + gap, fillAmt1, 500);
        order0 = exchange.getGridOrder(orderId);
        assertEq(orderQuoteAmt + leftQuoteAmt, order0.amount);
        assertEq(usdcVol1, fillVol);
        assertEq(fees1, fee);
        assertEq(fillAmt - fillAmt1, order0.revAmount);

        gridConf = exchange.getGridConfig(1);
        // grid profit
        assertEq(gridConf.profits, 0);
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            (fees >> 1) + (fees1 >> 1)
        );

        // taker balance
        assertEq(
            initialUSDCAmt + usdcVol0 - fees - usdcVol1 - fees1,
            usdc.balanceOf(taker)
        );
        assertEq(initialSEAAmt - fillAmt + fillAmt1, sea.balanceOf(taker));
    }

    function test_partialFillCompoundBidOrders() public {
        uint160 bidPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = bidPrice0 / 20; // 0.0001
        uint96 orderId = 0x000000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(
            address(sea),
            address(usdc),
            amt,
            0,
            10,
            0,
            bidPrice0,
            gap,
            true,
            500
        );

        (, uint128 totalQuoteAmt) = exchange.calcGridAmount(
            amt,
            bidPrice0,
            gap,
            0,
            10
        );
        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(totalQuoteAmt, usdc.balanceOf(address(exchange)));
        uint160 price0 = bidPrice0;
        uint160 price1 = bidPrice0 - gap;
        uint160 price2 = bidPrice0 - gap * 2;

        uint128 quoteAmt0 = exchange.calcQuoteAmount(amt, price0, false);
        uint128 quoteAmt1 = exchange.calcQuoteAmount(amt, price1, false);
        uint128 quoteAmt2 = exchange.calcQuoteAmount(amt, price2, false);
        IGridOrder.Order memory order0 = exchange.getGridOrder(orderId);
        IGridOrder.Order memory order1 = exchange.getGridOrder(orderId + 1);
        IGridOrder.Order memory order2 = exchange.getGridOrder(orderId + 2);
        assertEq(order0.amount, quoteAmt0);
        assertEq(order1.amount, quoteAmt1);
        assertEq(order2.amount, quoteAmt2);

        uint96[] memory orderIds = new uint96[](3);
        orderIds[0] = orderId;
        orderIds[1] = orderId + 1;
        orderIds[2] = orderId + 2;
        uint128[] memory amts = new uint128[](3);
        amts[0] = 100 ether + 8497464616475878697;
        amts[1] = 20000 ether - 7465167741434874343;
        amts[2] = 2000 ether + 542648971563646448;

        vm.startPrank(taker);
        exchange.fillBidOrders(1, orderIds, amts, amt + amt / 2, 0, 0);
        vm.stopPrank();

        assertEq(
            initialSEAAmt * 2,
            sea.balanceOf(maker) +
                sea.balanceOf(taker) +
                sea.balanceOf(address(exchange))
        );
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) +
                usdc.balanceOf(taker) +
                usdc.balanceOf(address(exchange))
        );
        // grid order flipped
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        order0 = exchange.getGridOrder(orderId);
        order1 = exchange.getGridOrder(orderId + 1);
        order2 = exchange.getGridOrder(orderId + 2);

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

        assertEq(quoteAmt0 - fillVol0 + makerFee(fee0), order0.amount);
        assertEq(quoteAmt1 - fillVol1 + makerFee(fee1), order1.amount);
        assertEq(quoteAmt2 - fillVol2 + makerFee(fee2), order2.amount);
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
        assertEq(gridConf.profits, 0);

        // taker balance
        assertEq(
            initialSEAAmt - amts[0] - amts[1] - amts[2],
            sea.balanceOf(taker)
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
}
