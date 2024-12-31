// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {IWETH} from "../src/interfaces/IWETH.sol";
import {IPair} from "../src/interfaces/IPair.sol";
import {IGridEx} from "../src/interfaces/IGridEx.sol";
import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
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

contract GridExCancelTest is GridExBaseTest {
    function test_cancelAskGridWithoutFill1() public {
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
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));

        vm.startPrank(maker);
        exchange.cancelGridOrders(1, maker, orderId, 10);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));

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

    function test_cancelAskGridWithoutFill2() public {
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
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));

        vm.startPrank(maker);
        exchange.cancelGridOrders(1, maker, orderId, 10);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));

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

    // compound grid
    function test_cancelAskGridFilled1() public {
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
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));

        vm.startPrank(taker);

        uint96[] memory orderIds = new uint96[](3);
        orderIds[0] = orderId;
        orderIds[1] = orderId + 1;
        orderIds[2] = orderId + 2;
        uint128[] memory amts = new uint128[](3);
        amts[0] = amt;
        amts[1] = amt;
        amts[2] = amt;
        exchange.fillAskOrders(1, orderIds, amts, amt * 3, 0);
        vm.stopPrank();

        vm.startPrank(maker);
        exchange.cancelGridOrders(1, maker, orderId, 10);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(initialSEAAmt - 3 * amt, sea.balanceOf(maker));
        assertEq(initialSEAAmt + 3 * amt, sea.balanceOf(taker));

        (uint128 vol0, uint128 fee0) = exchange.calcAskOrderQuoteAmount(
            askPrice0,
            amt,
            500
        );
        (uint128 vol1, uint128 fee1) = exchange.calcAskOrderQuoteAmount(
            askPrice0 + gap,
            amt,
            500
        );
        (uint128 vol2, uint128 fee2) = exchange.calcAskOrderQuoteAmount(
            askPrice0 + gap * 2,
            amt,
            500
        );
        uint128 protocolFee = (fee0 >> 1) + (fee1 >> 1) + (fee2 >> 1);
        uint128 totalVol = vol0 + vol1 + vol2;
        assertEq(protocolFee, usdc.balanceOf(address(exchange)));
        assertEq(
            protocolFee,
            exchange.protocolFees(Currency.wrap(address(usdc)))
        );
        assertEq(
            initialUSDCAmt - totalVol - fee0 - fee1 - fee2,
            usdc.balanceOf(taker)
        );
        assertEq(
            initialUSDCAmt + totalVol + fee0 + fee1 + fee2 - protocolFee,
            usdc.balanceOf(maker)
        );

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

    // not compound grid
    function test_cancelAskGridFilled2() public {
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
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));

        vm.startPrank(taker);

        uint96[] memory orderIds = new uint96[](3);
        orderIds[0] = orderId;
        orderIds[1] = orderId + 1;
        orderIds[2] = orderId + 2;
        uint128[] memory amts = new uint128[](3);
        amts[0] = amt;
        amts[1] = amt;
        amts[2] = amt;
        exchange.fillAskOrders(1, orderIds, amts, amt * 3, 0);
        vm.stopPrank();

        (uint128 vol0, uint128 fee0) = exchange.calcAskOrderQuoteAmount(
            askPrice0,
            amt,
            500
        );
        (uint128 vol1, uint128 fee1) = exchange.calcAskOrderQuoteAmount(
            askPrice0 + gap,
            amt,
            500
        );
        (uint128 vol2, uint128 fee2) = exchange.calcAskOrderQuoteAmount(
            askPrice0 + gap * 2,
            amt,
            500
        );
        uint128 protocolFee = (fee0 >> 1) + (fee1 >> 1) + (fee2 >> 1);
        uint128 totalVol = vol0 + vol1 + vol2;
        IGridOrder.GridConfig memory gridConf = exchange.getGridConfig(1);
        assertEq(
            gridConf.profits,
            (amt * gap * 3) /
                PRICE_MULTIPLIER +
                fee0 +
                fee1 +
                fee2 -
                protocolFee
        );

        vm.startPrank(maker);
        exchange.cancelGridOrders(1, maker, orderId, 10);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(initialSEAAmt - 3 * amt, sea.balanceOf(maker));
        assertEq(initialSEAAmt + 3 * amt, sea.balanceOf(taker));

        assertEq(
            protocolFee,
            exchange.protocolFees(Currency.wrap(address(usdc)))
        );
        assertEq(protocolFee, usdc.balanceOf(address(exchange)));
        assertEq(
            initialUSDCAmt - totalVol - fee0 - fee1 - fee2,
            usdc.balanceOf(taker)
        );
        assertEq(
            initialUSDCAmt + totalVol + fee0 + fee1 + fee2 - protocolFee,
            usdc.balanceOf(maker)
        );

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

    function test_cancelBidGridWithoutFill1() public {
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

        (, uint128 usdcTotal) = exchange.calcGridAmount(
            amt,
            bidPrice0,
            gap,
            0,
            10
        );
        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(usdcTotal, usdc.balanceOf(address(exchange)));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt - usdcTotal, usdc.balanceOf(maker));

        vm.startPrank(maker);
        exchange.cancelGridOrders(1, maker, orderId, 10);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));

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

    function test_cancelBidGridWithoutFill2() public {
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

        (, uint128 usdcTotal) = exchange.calcGridAmount(
            amt,
            bidPrice0,
            gap,
            0,
            10
        );
        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(usdcTotal, usdc.balanceOf(address(exchange)));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt - usdcTotal, usdc.balanceOf(maker));

        vm.startPrank(maker);
        exchange.cancelGridOrders(1, maker, orderId, 10);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
        assertEq(initialUSDCAmt, usdc.balanceOf(maker));

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

    // compound grid
    function test_cancelBidGridFilled1() public {
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

        vm.startPrank(taker);
        uint96[] memory orderIds = new uint96[](3);
        orderIds[0] = orderId;
        orderIds[1] = orderId + 1;
        orderIds[2] = orderId + 2;
        uint128[] memory amts = new uint128[](3);
        amts[0] = amt;
        amts[1] = amt;
        amts[2] = amt;
        exchange.fillBidOrders(1, orderIds, amts, amt * 3, 0);
        vm.stopPrank();

        vm.startPrank(maker);
        exchange.cancelGridOrders(1, maker, orderId, 10);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(initialSEAAmt + 3 * amt, sea.balanceOf(maker));
        assertEq(initialSEAAmt - 3 * amt, sea.balanceOf(taker));

        (uint128 vol0, uint128 fee0) = exchange.calcBidOrderQuoteAmount(
            bidPrice0,
            amt,
            500
        );
        (uint128 vol1, uint128 fee1) = exchange.calcBidOrderQuoteAmount(
            bidPrice0 - gap,
            amt,
            500
        );
        (uint128 vol2, uint128 fee2) = exchange.calcBidOrderQuoteAmount(
            bidPrice0 - gap * 2,
            amt,
            500
        );
        uint128 protocolFee = (fee0 >> 1) + (fee1 >> 1) + (fee2 >> 1);
        uint128 totalVol = vol0 + vol1 + vol2;
        assertEq(protocolFee, usdc.balanceOf(address(exchange)));
        assertEq(
            protocolFee,
            exchange.protocolFees(Currency.wrap(address(usdc)))
        );
        assertEq(
            initialUSDCAmt + totalVol - fee0 - fee1 - fee2,
            usdc.balanceOf(taker)
        );
        assertEq(
            initialUSDCAmt - totalVol + fee0 + fee1 + fee2 - protocolFee,
            usdc.balanceOf(maker)
        );

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

    // not compound grid
    function test_cancelBidGridFilled2() public {
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

        vm.startPrank(taker);
        uint96[] memory orderIds = new uint96[](3);
        orderIds[0] = orderId;
        orderIds[1] = orderId + 1;
        orderIds[2] = orderId + 2;
        uint128[] memory amts = new uint128[](3);
        amts[0] = amt;
        amts[1] = amt;
        amts[2] = amt;
        exchange.fillBidOrders(1, orderIds, amts, amt * 3, 0);
        vm.stopPrank();

        vm.startPrank(maker);
        exchange.cancelGridOrders(1, maker, orderId, 10);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(address(exchange)));
        assertEq(initialSEAAmt + 3 * amt, sea.balanceOf(maker));
        assertEq(initialSEAAmt - 3 * amt, sea.balanceOf(taker));

        (uint128 vol0, uint128 fee0) = exchange.calcBidOrderQuoteAmount(
            bidPrice0,
            amt,
            500
        );
        (uint128 vol1, uint128 fee1) = exchange.calcBidOrderQuoteAmount(
            bidPrice0 - gap,
            amt,
            500
        );
        (uint128 vol2, uint128 fee2) = exchange.calcBidOrderQuoteAmount(
            bidPrice0 - gap * 2,
            amt,
            500
        );
        uint128 protocolFee = (fee0 >> 1) + (fee1 >> 1) + (fee2 >> 1);
        uint128 totalVol = vol0 + vol1 + vol2;
        assertEq(protocolFee, usdc.balanceOf(address(exchange)));
        assertEq(
            protocolFee,
            exchange.protocolFees(Currency.wrap(address(usdc)))
        );
        assertEq(
            initialUSDCAmt + totalVol - fee0 - fee1 - fee2,
            usdc.balanceOf(taker)
        );
        assertEq(
            initialUSDCAmt - totalVol + fee0 + fee1 + fee2 - protocolFee,
            usdc.balanceOf(maker)
        );

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
}
