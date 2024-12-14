// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

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

import {GridExBaseTest} from './GridExBase.t.sol';

contract GridExFillTest is GridExBaseTest {
    function test_fillAskOrder() public {
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
            false,
            500
        );

        assertEq(amt * 10, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));

        vm.startPrank(taker);
        exchange.fillAskOrder(orderId, amt, amt);
        vm.stopPrank();

        // grid order flipped
        IGridOrder.Order memory order = exchange.getGridOrder(orderId);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(0, order.amount);
        assertEq((amt * (askPrice0 - gap)) / PRICE_MULTIPLIER, order.revAmount);
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

        // usdc balance
        (uint128 usdcVol, uint128 fees) = exchange.calcQuoteAmountForAskOrder(
            askPrice0,
            amt,
            500
        );
        assertEq(initialUSDCAmt - usdcVol - fees, usdc.balanceOf(taker));
        assertEq(usdcVol + fees, usdc.balanceOf(address(exchange)));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            fees >> 2
        );

        // grid profit
        assertEq(
            gridConf.profits,
            fees - (fees >> 2) + (amt * gap) / PRICE_MULTIPLIER
        );

        // fill reversed order
        vm.startPrank(taker);
        exchange.fillBidOrder(orderId, amt, amt);
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
        order = exchange.getGridOrder(orderId);
        assertEq(amt, order.amount);
        assertEq(0, order.revAmount);

        (uint128 usdcVol2, uint128 fees2) = exchange.calcQuoteAmountByBidOrder(
            askPrice0 - gap,
            amt,
            500
        );
        gridConf = exchange.getGridConfig(1);
        // grid profit
        assertEq(
            gridConf.profits,
            fees -
                (fees >> 2) +
                (amt * gap) /
                PRICE_MULTIPLIER +
                fees2 -
                (fees2 >> 2)
        );
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            (fees >> 2) + (fees2 >> 2)
        );

        // taker balance
        assertEq(
            initialUSDCAmt - usdcVol - fees + usdcVol2 - fees2,
            usdc.balanceOf(taker)
        );
        assertEq(initialSEAAmt, sea.balanceOf(taker));
    }

    function test_partialFillAskOrder() public {
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
            false,
            500
        );

        assertEq(amt * 10, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));

        uint128 fillAmt1 = 1000 ether;
        for (uint i = 0; i < amt / fillAmt1; i++) {
            vm.startPrank(taker);
            exchange.fillAskOrder(orderId, fillAmt1, fillAmt1);
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
        assertEq((amt * (askPrice0 - gap)) / PRICE_MULTIPLIER, order.revAmount);
        // sea balance
        assertEq(initialSEAAmt + amt, sea.balanceOf(taker));
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));

        // usdc balance
        (uint128 usdcVol, uint128 fees) = exchange.calcQuoteAmountForAskOrder(
            askPrice0,
            amt,
            500
        );
        assertEq(initialUSDCAmt - usdcVol - fees, usdc.balanceOf(taker));
        assertEq(usdcVol + fees, usdc.balanceOf(address(exchange)));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            fees >> 2
        );

        // grid profit
        assertEq(
            gridConf.profits,
            fees - (fees >> 2) + (amt * gap) / PRICE_MULTIPLIER
        );
    }

    // fill multiple ask orders
    function test_partialFillAskOrders() public {
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
            false,
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
        exchange.fillAskOrders(1, orderIds, amts, amt, 0);
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
        IGridOrder.Order memory order1 = exchange.getGridOrder(orderId+1);
        IGridOrder.Order memory order2 = exchange.getGridOrder(orderId+2);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(amt - amts[0], order0.amount);
        assertEq(amt - amts[1], order1.amount);
        uint128 amtFilled3 = amt - (amts[0]) - (amts[1]);
        assertEq(amt - amtFilled3, order2.amount);
        uint160 price0 = askPrice0;
        uint160 price1 = askPrice0 + gap;
        uint160 price2 = askPrice0 + gap*2;
        (uint128 vol0, uint128 revVol0, uint128 profit0, uint128 fee0) = calcQuoteVolReversed(price0, gap, amts[0], amt, 0, 500);
        (uint128 vol1, uint128 revVol1, uint128 profit1, uint128 fee1) = calcQuoteVolReversed(price1, gap, amts[1], amt, 0, 500);
        (uint128 vol2, uint128 revVol2, uint128 profit2, uint128 fee2) = calcQuoteVolReversed(price2, gap, amtFilled3, amt, 0, 500);
        // uint128 fillVol1 = calcQuoteVolReversed(amts[1], price1, true);
        // uint128 fillVol2 = calcQuoteVolReversed(amtFilled3, price2, true);
        assertEq(revVol0, order0.revAmount);
        assertEq(revVol1, order1.revAmount);
        assertEq(revVol2, order2.revAmount);
        assertEq(profit0, 0);
        assertEq(profit1, 0);
        assertEq(gridConf.profits, profit2);
        // sea balance
        assertEq(initialSEAAmt + amt, sea.balanceOf(taker));
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));

        uint128 fees = fee0 + fee1 + fee2;
        assertEq(initialUSDCAmt - vol0 - vol1 - vol2 - fees, usdc.balanceOf(taker));
        assertEq(vol0 + vol1 + vol2 + fees, usdc.balanceOf(address(exchange)));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            (fee0 >> 2) + (fee1 >> 2) + (fee2 >> 2)
        );

        // grid profit
        assertEq(
            gridConf.profits,
            profit2
            // fees - (fees >> 2) + (amt * gap) / PRICE_MULTIPLIER
        );
    }

    function test_fillBidOrder() public {
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
            false,
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
        exchange.fillBidOrder(orderId, amt, amt);
        vm.stopPrank();

        // grid order flipped
        IGridOrder.Order memory order = exchange.getGridOrder(orderId);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(0, order.amount);
        assertEq(amt, order.revAmount);
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
        (uint128 usdcVol, uint128 fees) = exchange.calcQuoteAmountByBidOrder(
            bidPrice0,
            amt,
            500
        );
        assertEq(initialUSDCAmt + usdcVol - fees, usdc.balanceOf(taker));
        assertEq(initialUSDCAmt - quoteAmt, usdc.balanceOf(maker));
        assertEq(quoteAmt - usdcVol + fees, usdc.balanceOf(address(exchange)));
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            fees >> 2
        );

        // grid profit
        assertEq(gridConf.profits, fees - (fees >> 2));

        // fill reversed order
        vm.startPrank(taker);
        exchange.fillAskOrder(orderId, amt, amt);
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
        order = exchange.getGridOrder(orderId);
        assertEq((amt * bidPrice0) / PRICE_MULTIPLIER, order.amount);
        assertEq(0, order.revAmount);

        // maker balance not change
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt - quoteAmt, usdc.balanceOf(maker));

        (uint128 usdcVol2, uint128 fees2) = exchange.calcQuoteAmountForAskOrder(
            bidPrice0 + gap,
            amt,
            500
        );
        gridConf = exchange.getGridConfig(1);
        // grid profit
        assertEq(
            gridConf.profits,
            fees -
                (fees >> 2) +
                (amt * gap) /
                PRICE_MULTIPLIER +
                fees2 -
                (fees2 >> 2)
        );
        assertEq(
            exchange.protocolFees(Currency.wrap(address(usdc))),
            (fees >> 2) + (fees2 >> 2)
        );

        // taker balance
        assertEq(
            initialUSDCAmt + usdcVol - fees - usdcVol2 - fees2,
            usdc.balanceOf(taker)
        );
        assertEq(initialSEAAmt, sea.balanceOf(taker));
    }
}
