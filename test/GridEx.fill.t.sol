// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {Lens} from "../src/libraries/Lens.sol";
import {GridExBaseTest} from "./GridExBase.t.sol";

contract GridExFillTest is GridExBaseTest {
    function test_fillAskOrder() public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = askPrice0 / 20; // 0.0001
        // uint96 orderId = 0x800000000000000000000001;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(address(sea), address(usdc), amt, 10, 0, askPrice0, askPrice0 - gap, gap, false, 500);

        assertEq(amt * 10, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));

        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        assertEq(gridConf.pairId, 1);
        (Currency base, Currency quote,) = exchange.getPairById(gridConf.pairId);
        assertEq(Currency.unwrap(base), address(sea));
        assertEq(Currency.unwrap(quote), address(usdc));

        uint256 gridOrderId = toGridOrderId(1, orderId);
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, amt, new bytes(0), 0);
        vm.stopPrank();

        // grid order flipped
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);

        assertEq(0, order.amount);
        assertEq((amt * (askPrice0 - gap)) / PRICE_MULTIPLIER, order.revAmount);
        // sea balance
        assertEq(initialSEAAmt + amt, sea.balanceOf(taker));
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );

        // usdc balance
        (uint128 usdcVol, uint128 fees) = Lens.calcAskOrderQuoteAmount(askPrice0, amt, 500);
        assertEq(initialUSDCAmt - usdcVol - fees, usdc.balanceOf(taker));
        assertEq(usdcVol + fees, usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault));
        assertEq(calcProtocolFee(fees), usdc.balanceOf(vault));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));
        // assertEq(
        //     exchange.protocolProfits(Currency.wrap(address(usdc))),
        //     fees >> 1
        // );

        // grid profit
        gridConf = exchange.getGridConfig(1);
        assertEq(gridConf.profits, calcMakerFee(fees) + (amt * gap) / PRICE_MULTIPLIER);

        // fill reversed order
        vm.startPrank(taker);
        exchange.fillBidOrder(gridOrderId, amt, amt, new bytes(0), 0);
        vm.stopPrank();

        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        order = exchange.getGridOrder(gridOrderId);
        assertEq(amt, order.amount);
        assertEq(0, order.revAmount);

        (uint128 usdcVol2, uint128 fees2) = Lens.calcBidOrderQuoteAmount(askPrice0 - gap, amt, 500);
        gridConf = exchange.getGridConfig(1);
        // grid profit
        assertEq(
            gridConf.profits,
            // fees -
            calcMakerFee(fees) + (amt * gap) / PRICE_MULTIPLIER + calcMakerFee(fees2) // -
        );
        // assertEq(
        //     exchange.protocolProfits(Currency.wrap(address(usdc))),
        //     (fees >> 1) + (fees2 >> 1)
        // );

        // taker balance
        assertEq(initialUSDCAmt - usdcVol - fees + usdcVol2 - fees2, usdc.balanceOf(taker));
        assertEq(initialSEAAmt, sea.balanceOf(taker));
    }

    function test_partialFillAskOrder() public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = askPrice0 / 20; // 0.0001
        // uint96 orderId = 0x800000000000000000000001;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(address(sea), address(usdc), amt, 10, 0, askPrice0, 0, gap, false, 500);

        assertEq(amt * 10, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));

        uint256 gridOrderId = toGridOrderId(1, orderId);
        uint128 fillAmt1 = 1000 ether;
        for (uint256 i = 0; i < amt / fillAmt1; i++) {
            vm.startPrank(taker);
            exchange.fillAskOrder(gridOrderId, fillAmt1, fillAmt1, new bytes(0), 0);
            vm.stopPrank();

            assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
            assertEq(
                initialUSDCAmt * 2,
                usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange))
                    + usdc.balanceOf(vault)
            );
        }

        // grid order flipped
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(0, order.amount);
        assertEq((amt * (askPrice0 - gap)) / PRICE_MULTIPLIER, order.revAmount);
        // sea balance
        assertEq(initialSEAAmt + amt, sea.balanceOf(taker));
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));

        // usdc balance
        (uint128 usdcVol, uint128 fees) = Lens.calcAskOrderQuoteAmount(askPrice0, amt, 500);
        assertEq(initialUSDCAmt - usdcVol - fees, usdc.balanceOf(taker));
        assertEq(usdcVol + fees, usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));
        // assertEq(
        //     exchange.protocolProfits(Currency.wrap(address(usdc))),
        //     fees >> 1
        // );

        // grid profit
        assertEq(gridConf.profits, calcMakerFee(fees) + (amt * gap) / PRICE_MULTIPLIER);
    }

    // fill multiple ask orders
    function test_partialFillAskOrders() public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = askPrice0 / 20; // 0.0001
        // uint96 orderId = 0x800000000000000000000001;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(address(sea), address(usdc), amt, 10, 0, askPrice0, 0, gap, false, 500);

        assertEq(amt * 10, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));

        vm.startPrank(taker);

        uint256[] memory orderIds = new uint256[](3);
        orderIds[0] = toGridOrderId(1, orderId);
        orderIds[1] = toGridOrderId(1, orderId + 1);
        orderIds[2] = toGridOrderId(1, orderId + 2);
        uint128[] memory amts = new uint128[](3);
        amts[0] = 10 ether + 783544866523132175;
        amts[1] = 200 ether + 54648971563646448;
        amts[2] = 20000 ether - 4897895643465416784;
        exchange.fillAskOrders(1, orderIds, amts, amt, 0, new bytes(0), 0);
        vm.stopPrank();

        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
        // grid order flipped
        IGridOrder.OrderInfo memory order0 = exchange.getGridOrder(orderIds[0]);
        IGridOrder.OrderInfo memory order1 = exchange.getGridOrder(orderIds[1]);
        IGridOrder.OrderInfo memory order2 = exchange.getGridOrder(orderIds[2]);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(amt - amts[0], order0.amount);
        assertEq(amt - amts[1], order1.amount);
        uint128 amtFilled3 = amt - (amts[0]) - (amts[1]);
        assertEq(amt - amtFilled3, order2.amount);
        uint256 price0 = askPrice0;
        uint256 price1 = askPrice0 + gap;
        uint256 price2 = askPrice0 + gap * 2;
        (uint128 vol0, uint128 revVol0, uint128 profit0, uint128 fee0) =
            calcQuoteVolReversed(price0, gap, amts[0], amt, 0, 500);
        (uint128 vol1, uint128 revVol1, uint128 profit1, uint128 fee1) =
            calcQuoteVolReversed(price1, gap, amts[1], amt, 0, 500);
        (uint128 vol2, uint128 revVol2, uint128 profit2, uint128 fee2) =
            calcQuoteVolReversed(price2, gap, amtFilled3, amt, 0, 500);
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
        assertEq(vol0 + vol1 + vol2 + fees, usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));
        // assertEq(
        //     exchange.protocolProfits(Currency.wrap(address(usdc))),
        //     (fee0 >> 1) + (fee1 >> 1) + (fee2 >> 1)
        // );

        // grid profit
        assertEq(gridConf.profits, profit2);
    }

    function test_fillBidOrder() public {
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = bidPrice0 / 20; // 0.0001
        // uint96 orderId = 0x000000000000000000000001;
        uint128 orderId = 0x00000000000000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(address(sea), address(usdc), amt, 0, 10, 0, bidPrice0, gap, false, 500);

        uint128 quoteAmt = 0;
        uint256 price = bidPrice0;
        for (int256 i = 0; i < 10; i++) {
            quoteAmt += Lens.calcQuoteAmount(amt, price, false);
            price = price - gap;
        }

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(quoteAmt, usdc.balanceOf(address(exchange)));

        uint256 gridOrderId = toGridOrderId(1, orderId);
        vm.startPrank(taker);
        exchange.fillBidOrder(gridOrderId, amt, amt, new bytes(0), 0);
        vm.stopPrank();

        // grid order flipped
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);

        assertEq(0, order.amount);
        assertEq(amt, order.revAmount);
        // sea balance
        assertEq(initialSEAAmt - amt, sea.balanceOf(taker));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );

        // usdc balance
        (uint128 usdcVol, uint128 fees) = Lens.calcBidOrderQuoteAmount(bidPrice0, amt, 500);
        assertEq(initialUSDCAmt + usdcVol - fees, usdc.balanceOf(taker));
        assertEq(initialUSDCAmt - quoteAmt, usdc.balanceOf(maker));
        assertEq(quoteAmt - usdcVol + fees, usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault));
        // assertEq(
        //     exchange.protocolProfits(Currency.wrap(address(usdc))),
        //     fees >> 1
        // );

        // grid profit
        assertEq(gridConf.profits, calcMakerFee(fees));

        // fill reversed order
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, amt, new bytes(0), 0);
        vm.stopPrank();

        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        order = exchange.getGridOrder(gridOrderId);
        assertEq((amt * bidPrice0) / PRICE_MULTIPLIER, order.amount);
        assertEq(0, order.revAmount);

        // maker balance not change
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt - quoteAmt, usdc.balanceOf(maker));

        (uint128 usdcVol2, uint128 fees2) = Lens.calcAskOrderQuoteAmount(bidPrice0 + gap, amt, 500);
        gridConf = exchange.getGridConfig(1);
        // grid profit
        assertEq(
            gridConf.profits,
            // fees -
            calcMakerFee(fees) + (amt * gap) / PRICE_MULTIPLIER
            // fees2 -
            + calcMakerFee(fees2)
        );
        // assertEq(
        //     exchange.protocolProfits(Currency.wrap(address(usdc))),
        //     (fees >> 1) + (fees2 >> 1)
        // );

        // taker balance
        assertEq(initialUSDCAmt + usdcVol - fees - usdcVol2 - fees2, usdc.balanceOf(taker));
        assertEq(initialSEAAmt, sea.balanceOf(taker));
    }

    function test_partialFillBidOrder() public {
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = bidPrice0 / 20; // 0.0001
        uint128 orderId = 0x000000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(address(sea), address(usdc), amt, 0, 10, 0, bidPrice0, gap, false, 500);

        // uint128 quoteAmt = 0;
        // uint256 price = bidPrice0;
        // for (int i = 0; i < 10; i++) {
        //     quoteAmt += Lens.calcQuoteAmount(amt, price, false);
        //     price = price - gap;
        // }
        (, uint128 totalQuoteAmt) = Lens.calcGridAmount(amt, bidPrice0, gap, 0, 10);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(totalQuoteAmt, usdc.balanceOf(address(exchange)));
        IGridOrder.OrderInfo memory order0 = exchange.getGridOrder(gridOrderId);
        assertEq(0, order0.revAmount);
        uint128 quoteAmt0 = Lens.calcQuoteAmount(amt, bidPrice0, false);
        assertEq(quoteAmt0, order0.amount);

        uint128 fillAmt = amt - 45455424988975486;
        vm.startPrank(taker);
        exchange.fillBidOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );

        // grid order flipped
        order0 = exchange.getGridOrder(gridOrderId);

        // usdc balance
        (uint128 usdcVol0, uint128 fees) = Lens.calcBidOrderQuoteAmount(bidPrice0, fillAmt, 500);
        assertEq(quoteAmt0 - usdcVol0, order0.amount);
        assertEq(fillAmt, order0.revAmount);
        // sea balance
        assertEq(initialSEAAmt - fillAmt, sea.balanceOf(taker));
        assertEq(initialSEAAmt, sea.balanceOf(maker));

        assertEq(initialUSDCAmt + usdcVol0 - fees, usdc.balanceOf(taker));
        assertEq(initialUSDCAmt - totalQuoteAmt, usdc.balanceOf(maker));
        assertEq(totalQuoteAmt - usdcVol0 + fees, usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault));
        // assertEq(
        //     exchange.protocolProfits(Currency.wrap(address(usdc))),
        //     fees >> 1
        // );

        // grid profit
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        assertEq(gridConf.profits, calcMakerFee(fees));

        // fill reversed order
        uint128 fillAmt1 = fillAmt - 4156489783946137867;
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, fillAmt1, 0, new bytes(0), 0);
        vm.stopPrank();

        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        // maker balance not change
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt - totalQuoteAmt, usdc.balanceOf(maker));

        (uint128 usdcVol1, uint128 fees1) = Lens.calcAskOrderQuoteAmount(bidPrice0 + gap, fillAmt1, 500);
        (uint128 fillVol, uint128 orderQuoteAmt, uint128 profit, uint128 fee) =
            calcQuoteVolReversed(bidPrice0 + gap, gap, fillAmt1, amt, quoteAmt0 - usdcVol0, 500);
        order0 = exchange.getGridOrder(gridOrderId);
        assertEq(orderQuoteAmt, order0.amount);
        assertEq(usdcVol1, fillVol);
        assertEq(fees1, fee);
        assertEq(fillAmt - fillAmt1, order0.revAmount);

        gridConf = exchange.getGridConfig(1);
        // grid profit
        assertEq(gridConf.profits, calcMakerFee(fees) + profit);
        // (amt * gap) /
        // PRICE_MULTIPLIER +
        // fees1 -
        // (fees1 >> 1)
        // assertEq(
        //     exchange.protocolProfits(Currency.wrap(address(usdc))),
        //     (fees >> 1) + (fees1 >> 1)
        // );

        // taker balance
        assertEq(initialUSDCAmt + usdcVol0 - fees - usdcVol1 - fees1, usdc.balanceOf(taker));
        assertEq(initialSEAAmt - fillAmt + fillAmt1, sea.balanceOf(taker));
    }

    function test_partialFillBidOrders() public {
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = bidPrice0 / 20; // 0.0001
        uint128 orderId = 0x000000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(address(sea), address(usdc), amt, 0, 10, 0, bidPrice0, gap, false, 500);

        (, uint128 totalQuoteAmt) = Lens.calcGridAmount(amt, bidPrice0, gap, 0, 10);
        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(totalQuoteAmt, usdc.balanceOf(address(exchange)));
        uint256 price0 = bidPrice0;
        uint256 price1 = bidPrice0 - gap;
        uint256 price2 = bidPrice0 - gap * 2;

        uint128 quoteAmt0 = Lens.calcQuoteAmount(amt, price0, false);
        uint128 quoteAmt1 = Lens.calcQuoteAmount(amt, price1, false);
        uint128 quoteAmt2 = Lens.calcQuoteAmount(amt, price2, false);
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
        amts[0] = 100 ether + 8497464616475878697;
        amts[1] = 20000 ether - 7465167741434874343;
        amts[2] = 2000 ether + 542648971563646448;

        vm.startPrank(taker);
        exchange.fillBidOrders(1, orderIds, amts, amt + amt / 2, 0, new bytes(0), 0);
        vm.stopPrank();

        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt * 2,
            usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)) + usdc.balanceOf(vault)
        );
        // grid order flipped
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        order0 = exchange.getGridOrder(orderIds[0]);
        order1 = exchange.getGridOrder(orderIds[1]);
        order2 = exchange.getGridOrder(orderIds[2]);

        (uint128 fillVol0, uint128 fee0) = Lens.calcBidOrderQuoteAmount(price0, amts[0], 500);
        (uint128 fillVol1, uint128 fee1) = Lens.calcBidOrderQuoteAmount(price1, amts[1], 500);
        (uint128 fillVol2, uint128 fee2) = Lens.calcBidOrderQuoteAmount(price2, amts[2], 500);

        assertEq(quoteAmt0 - fillVol0, order0.amount);
        assertEq(quoteAmt1 - fillVol1, order1.amount);
        assertEq(quoteAmt2 - fillVol2, order2.amount);
        // uint128 fillVol1 = calcQuoteVolReversed(amts[1], price1, true);
        // uint128 fillVol2 = calcQuoteVolReversed(amtFilled3, price2, true);
        assertEq(amts[0], order0.revAmount);
        assertEq(amts[1], order1.revAmount);
        assertEq(amts[2], order2.revAmount);

        // grid profits
        uint128 protocolFee = calcProtocolFee(fee0) + calcProtocolFee(fee1) + calcProtocolFee(fee2);
        // protocol profits
        // assertEq(
        //     exchange.protocolProfits(Currency.wrap(address(usdc))),
        //     protocolFee
        // );
        assertEq(gridConf.profits, fee0 + fee1 + fee2 - protocolFee);

        // taker balance
        assertEq(initialSEAAmt - amts[0] - amts[1] - amts[2], sea.balanceOf(taker));
        assertEq(initialUSDCAmt + fillVol0 - fee0 + fillVol1 - fee1 + fillVol2 - fee2, usdc.balanceOf(taker));

        // maker balance
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt - totalQuoteAmt, usdc.balanceOf(maker));
    }
}
