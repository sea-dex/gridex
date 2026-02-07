// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {Lens} from "../src/libraries/Lens.sol";
import {GridExBaseTest} from "./GridExBase.t.sol";

contract GridExCancelETHTest is GridExBaseTest {
    Currency eth = Currency.wrap(address(0));

    function test_cancelETHAskGridWithoutFill1() public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = askPrice0 / 20; // 0.0001
        // uint96 orderId = 0x800000000000000000000001;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 2 ether / 100; // SEA

        _placeOrders(address(0), address(usdc), amt, 10, 0, askPrice0, 0, gap, true, 500);
        assertEq(amt * 10, weth.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(initialETHAmt - 10 * amt, eth.balanceOf(maker));

        vm.startPrank(maker);
        exchange.cancelGridOrders(maker, toGridOrderId(1, orderId), 10, 1);
        vm.stopPrank();

        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(0, weth.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(initialETHAmt, eth.balanceOf(maker));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));

        assertEq(initialETHAmt * 2, eth.balanceOf(maker) + eth.balanceOf(taker) + weth.balanceOf(address(exchange)));
        assertEq(initialUSDCAmt * 2, usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)));
    }

    function test_cancelETHAskGridWithoutFill2() public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = askPrice0 / 20; // 0.0001
        // uint96 orderId = 0x800000000000000000000001;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 2 ether / 100; // SEA

        _placeOrders(address(0), address(usdc), amt, 10, 0, askPrice0, 0, gap, false, 500);
        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(amt * 10, weth.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(initialETHAmt - 10 * amt, eth.balanceOf(maker));

        vm.startPrank(maker);
        exchange.cancelGridOrders(maker, toGridOrderId(1, orderId), 10, 0);
        vm.stopPrank();

        assertEq(0, weth.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(amt * 10, weth.balanceOf(maker));
        assertEq(initialETHAmt, eth.balanceOf(maker) + weth.balanceOf(maker));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));

        assertEq(initialETHAmt, eth.balanceOf(maker) + weth.balanceOf(maker) + eth.balanceOf(address(exchange)));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker) + usdc.balanceOf(address(exchange)));
    }

    // compound grid
    function test_cancelETHAskGridFilled1() public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = askPrice0 / 20; // 0.0001
        // uint96 orderId = 0x800000000000000000000001;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 2 ether / 100; // SEA

        _placeOrders(address(0), address(usdc), amt, 10, 0, askPrice0, 0, gap, true, 500);
        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(amt * 10, weth.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(initialETHAmt - 10 * amt, eth.balanceOf(maker));
        assertEq(0, weth.balanceOf(maker));

        uint256[] memory orderIds = new uint256[](3);
        orderIds[0] = toGridOrderId(1, orderId);
        orderIds[1] = toGridOrderId(1, orderId + 1);
        orderIds[2] = toGridOrderId(1, orderId + 2);
        uint128[] memory amts = new uint128[](3);
        amts[0] = amt;
        amts[1] = amt;
        amts[2] = amt;

        vm.startPrank(taker);
        exchange.fillAskOrders(1, orderIds, amts, amt * 3, 0, new bytes(0), 2);
        vm.stopPrank();

        vm.startPrank(maker);
        exchange.cancelGridOrders(maker, toGridOrderId(1, orderId), 10, 1);
        vm.stopPrank();

        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(0, weth.balanceOf(address(exchange)));
        assertEq(initialETHAmt - 3 * amt, eth.balanceOf(maker));
        assertEq(initialETHAmt + 3 * amt, eth.balanceOf(taker));
        assertEq(0, weth.balanceOf(maker));
        assertEq(0, weth.balanceOf(taker));

        (uint128 vol0, uint128 fee0) = Lens.calcAskOrderQuoteAmount(askPrice0, amt, 500);
        (uint128 vol1, uint128 fee1) = Lens.calcAskOrderQuoteAmount(askPrice0 + gap, amt, 500);
        (uint128 vol2, uint128 fee2) = Lens.calcAskOrderQuoteAmount(askPrice0 + gap * 2, amt, 500);
        uint128 protocolFee = calcProtocolFee(fee0) + calcProtocolFee(fee1) + calcProtocolFee(fee2);
        uint128 totalVol = vol0 + vol1 + vol2;
        assertEq(protocolFee, usdc.balanceOf(address(exchange)));
        // assertEq(
        //     protocolFee,
        //     exchange.protocolProfits(Currency.wrap(address(usdc)))
        // );
        assertEq(initialUSDCAmt - totalVol - fee0 - fee1 - fee2, usdc.balanceOf(taker));
        assertEq(initialUSDCAmt + totalVol + fee0 + fee1 + fee2 - protocolFee, usdc.balanceOf(maker));

        assertEq(initialETHAmt * 2, eth.balanceOf(maker) + eth.balanceOf(taker));
        assertEq(initialUSDCAmt * 2, usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)));
    }

    // not compound grid
    function test_cancelETHAskGridFilled2() public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = askPrice0 / 20; // 0.0001
        // uint96 orderId = 0x800000000000000000000001;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 2 ether / 100; // SEA

        _placeOrders(address(0), address(usdc), amt, 10, 0, askPrice0, 0, gap, false, 500);
        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(amt * 10, weth.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(initialETHAmt - 10 * amt, eth.balanceOf(maker));

        uint256[] memory orderIds = new uint256[](3);
        orderIds[0] = toGridOrderId(1, orderId);
        orderIds[1] = toGridOrderId(1, orderId + 1);
        orderIds[2] = toGridOrderId(1, orderId + 2);
        uint128[] memory amts = new uint128[](3);
        amts[0] = amt;
        amts[1] = amt;
        amts[2] = amt;

        vm.startPrank(taker);
        exchange.fillAskOrders(1, orderIds, amts, amt * 3, 0, new bytes(0), 2);
        vm.stopPrank();

        (uint128 vol0, uint128 fee0) = Lens.calcAskOrderQuoteAmount(askPrice0, amt, 500);
        (uint128 vol1, uint128 fee1) = Lens.calcAskOrderQuoteAmount(askPrice0 + gap, amt, 500);
        (uint128 vol2, uint128 fee2) = Lens.calcAskOrderQuoteAmount(askPrice0 + gap * 2, amt, 500);
        uint128 protocolFee = calcProtocolFee(fee0) + calcProtocolFee(fee1) + calcProtocolFee(fee2);
        uint128 totalVol = vol0 + vol1 + vol2;
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        assertEq(gridConf.profits, (amt * gap * 3) / PRICE_MULTIPLIER + fee0 + fee1 + fee2 - protocolFee);

        vm.startPrank(maker);
        exchange.cancelGridOrders(maker, toGridOrderId(1, orderId), 10, 0);
        vm.stopPrank();

        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(0, weth.balanceOf(address(exchange)));
        assertEq(initialETHAmt - 10 * amt, eth.balanceOf(maker));
        assertEq(7 * amt, weth.balanceOf(maker));
        assertEq(initialETHAmt + 3 * amt, eth.balanceOf(taker));

        // assertEq(
        //     protocolFee,
        //     exchange.protocolProfits(Currency.wrap(address(usdc)))
        // );
        assertEq(protocolFee + gridConf.profits, usdc.balanceOf(address(exchange)));
        assertEq(initialUSDCAmt - totalVol - fee0 - fee1 - fee2, usdc.balanceOf(taker));
        assertEq(initialUSDCAmt + totalVol + fee0 + fee1 + fee2 - protocolFee - gridConf.profits, usdc.balanceOf(maker));

        assertEq(initialUSDCAmt * 2, usdc.balanceOf(maker) + usdc.balanceOf(taker) + usdc.balanceOf(address(exchange)));
    }

    function test_cancelETHBidGridWithoutFill1() public {
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500); // 0.002
        uint256 gap = bidPrice0 / 20; // 0.0001
        uint128 orderId = 0x000000000000000000000001;
        uint128 amt = 20 ether; // SEA

        _placeOrders(address(sea), address(0), amt, 0, 10, 0, bidPrice0, gap, false, 500);

        (, uint128 ethTotal) = Lens.calcGridAmount(amt, bidPrice0, gap, 0, 10);
        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(ethTotal, weth.balanceOf(address(exchange)));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialETHAmt - ethTotal, eth.balanceOf(maker));

        vm.startPrank(maker);
        exchange.cancelGridOrders(maker, toGridOrderId(1, orderId), 10, 2);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(0, weth.balanceOf(address(exchange)));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialETHAmt, eth.balanceOf(maker));

        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(initialETHAmt * 2, eth.balanceOf(maker) + eth.balanceOf(taker) + weth.balanceOf(address(exchange)));
    }

    function test_cancelETHBidGridWithoutFill2() public {
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500); // 0.002
        uint256 gap = bidPrice0 / 20; // 0.0001
        uint128 orderId = 0x000000000000000000000001;
        uint128 amt = 20 ether; // SEA

        _placeOrders(address(sea), address(0), amt, 0, 10, 0, bidPrice0, gap, false, 500);

        (, uint128 ethTotal) = Lens.calcGridAmount(amt, bidPrice0, gap, 0, 10);
        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(ethTotal, weth.balanceOf(address(exchange)));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialETHAmt - ethTotal, eth.balanceOf(maker));

        vm.startPrank(maker);
        exchange.cancelGridOrders(maker, toGridOrderId(1, orderId), 10, 0);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(0, eth.balanceOf(address(exchange)));
        assertEq(0, weth.balanceOf(address(exchange)));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialETHAmt - ethTotal, eth.balanceOf(maker));
        assertEq(ethTotal, weth.balanceOf(maker));

        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
    }

    // compound grid
    function test_cancelETHBidGridFilled1() public {
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500); // 0.002
        uint256 gap = bidPrice0 / 20; // 0.0001
        uint128 orderId = 0x000000000000000000000001;
        uint128 amt = 20 ether; // SEA

        _placeOrders(address(sea), address(0), amt, 0, 10, 0, bidPrice0, gap, true, 500);

        uint256[] memory orderIds = new uint256[](3);
        orderIds[0] = toGridOrderId(1, orderId);
        orderIds[1] = toGridOrderId(1, orderId + 1);
        orderIds[2] = toGridOrderId(1, orderId + 2);
        uint128[] memory amts = new uint128[](3);
        amts[0] = amt;
        amts[1] = amt;
        amts[2] = amt;

        vm.startPrank(taker);
        exchange.fillBidOrders(1, orderIds, amts, amt * 3, 0, new bytes(0), 2); // intoken: SEA
        vm.stopPrank();

        vm.startPrank(maker);
        exchange.cancelGridOrders(maker, toGridOrderId(1, orderId), 10, 2);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(initialSEAAmt + 3 * amt, sea.balanceOf(maker));
        assertEq(initialSEAAmt - 3 * amt, sea.balanceOf(taker));

        (uint128 vol0, uint128 fee0) = Lens.calcBidOrderQuoteAmount(bidPrice0, amt, 500);
        (uint128 vol1, uint128 fee1) = Lens.calcBidOrderQuoteAmount(bidPrice0 - gap, amt, 500);
        (uint128 vol2, uint128 fee2) = Lens.calcBidOrderQuoteAmount(bidPrice0 - gap * 2, amt, 500);
        uint128 protocolFee = calcProtocolFee(fee0) + calcProtocolFee(fee1) + calcProtocolFee(fee2);
        uint128 totalVol = vol0 + vol1 + vol2;
        assertEq(protocolFee, weth.balanceOf(vault));
        // assertEq(
        //     protocolFee,
        //     exchange.protocolProfits(Currency.wrap(address(weth)))
        // );
        assertEq(initialETHAmt + totalVol - fee0 - fee1 - fee2, eth.balanceOf(taker));
        assertEq(initialETHAmt - totalVol + fee0 + fee1 + fee2 - protocolFee, eth.balanceOf(maker));

        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) + eth.balanceOf(taker) + weth.balanceOf(address(exchange)) + weth.balanceOf(vault)
        );
    }

    // not compound grid
    function test_cancelETHBidGridFilled2() public {
        uint256 bidPrice0 = uint256(PRICE_MULTIPLIER / 500); // 0.002
        uint256 gap = bidPrice0 / 20; // 0.0001
        uint128 orderId = 0x000000000000000000000001;
        uint128 amt = 20 ether; // SEA

        _placeOrders(address(sea), address(0), amt, 0, 10, 0, bidPrice0, gap, true, 500);

        uint256[] memory orderIds = new uint256[](3);
        orderIds[0] = toGridOrderId(1, orderId);
        orderIds[1] = toGridOrderId(1, orderId + 1);
        orderIds[2] = toGridOrderId(1, orderId + 2);
        uint128[] memory amts = new uint128[](3);
        amts[0] = amt;
        amts[1] = amt;
        amts[2] = amt;

        vm.startPrank(taker);
        exchange.fillBidOrders(1, orderIds, amts, amt * 3, 0, new bytes(0), 2); // intoken: SEA
        vm.stopPrank();

        vm.startPrank(maker);
        exchange.cancelGridOrders(maker, toGridOrderId(1, orderId), 10, 0);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(initialSEAAmt + 3 * amt, sea.balanceOf(maker));
        assertEq(initialSEAAmt - 3 * amt, sea.balanceOf(taker));

        (uint128 vol0, uint128 fee0) = Lens.calcBidOrderQuoteAmount(bidPrice0, amt, 500);
        (uint128 vol1, uint128 fee1) = Lens.calcBidOrderQuoteAmount(bidPrice0 - gap, amt, 500);
        (uint128 vol2, uint128 fee2) = Lens.calcBidOrderQuoteAmount(bidPrice0 - gap * 2, amt, 500);
        uint128 protocolFee = calcProtocolFee(fee0) + calcProtocolFee(fee1) + calcProtocolFee(fee2);
        uint128 totalVol = vol0 + vol1 + vol2;
        assertEq(protocolFee, weth.balanceOf(vault));
        // assertEq(
        //     protocolFee,
        //     exchange.protocolProfits(Currency.wrap(address(weth)))
        // );
        assertEq(initialETHAmt + totalVol - fee0 - fee1 - fee2, eth.balanceOf(taker));
        (, uint128 ethTotal) = Lens.calcGridAmount(amt, bidPrice0, gap, 0, 10);
        assertEq(initialETHAmt - ethTotal, eth.balanceOf(maker));
        assertEq(ethTotal - totalVol + fee0 + fee1 + fee2 - protocolFee, weth.balanceOf(maker));

        assertEq(initialSEAAmt * 2, sea.balanceOf(maker) + sea.balanceOf(taker) + sea.balanceOf(address(exchange)));
        assertEq(
            initialETHAmt * 2,
            eth.balanceOf(maker) + weth.balanceOf(maker) + eth.balanceOf(taker) + weth.balanceOf(address(exchange))
                + weth.balanceOf(vault)
        );
    }
}
