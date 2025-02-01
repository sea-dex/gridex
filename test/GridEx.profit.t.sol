// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IWETH} from "../src/interfaces/IWETH.sol";
import {IPair} from "../src/interfaces/IPair.sol";
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

contract GridExProfitTest is GridExBaseTest {
    Currency eth = Currency.wrap(address(0));

    function test_profitAskOrder() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        // uint96 orderId = 0x800000000000000000000001;
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
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));

        (uint128 ethVol, uint128 fees) = exchange.calcAskOrderQuoteAmount(
            askPrice0,
            amt,
            500
        );

        uint256 gridOrderId = toGridOrderId(1, orderId);
        vm.startPrank(taker);
        exchange.fillAskOrder{value: ethVol + fees}(gridOrderId, amt, amt, 1);
        vm.stopPrank();

        assertEq(fees / 2, exchange.protocolFees(Currency.wrap(address(weth))));

        address third = address(0x300);

        vm.startPrank(third);
        vm.expectRevert();
        exchange.withdrawGridProfits(1, fees / 4, third, 0);
        vm.stopPrank();

        vm.startPrank(third);
        vm.expectRevert();
        exchange.collectProtocolFee(
            Currency.wrap(address(weth)),
            third,
            fees / 4,
            0
        );
        vm.stopPrank();

        exchange.collectProtocolFee(
            Currency.wrap(address(weth)),
            third,
            fees / 4,
            0
        );
        assertEq(fees / 4, weth.balanceOf(third));

        exchange.collectProtocolFee(Currency.wrap(address(weth)), third, 0, 1);
        assertEq(fees / 2 - fees / 4 - 1, eth.balanceOf(third));

        vm.startPrank(maker);
        exchange.withdrawGridProfits(1, fees / 4, maker, 0);
        vm.stopPrank();
        assertEq(fees / 4, weth.balanceOf(maker));

        vm.startPrank(maker);
        exchange.withdrawGridProfits(1, 0, maker, 1);
        vm.stopPrank();

        uint128 gapProfit = uint128((amt * gap) / PRICE_MULTIPLIER);
        assertEq(
            initialETHAmt + gapProfit + fees - (fees >> 1) - fees / 4,
            eth.balanceOf(maker)
        );
    }
}
