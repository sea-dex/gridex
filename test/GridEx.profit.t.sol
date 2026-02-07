// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Currency} from "../src/libraries/Currency.sol";
import {Lens} from "../src/libraries/Lens.sol";
import {GridExBaseTest} from "./GridExBase.t.sol";

contract GridExProfitTest is GridExBaseTest {
    Currency eth = Currency.wrap(address(0));

    function test_profitAskOrder() public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500); // 0.002
        uint256 gap = askPrice0 / 20; // 0.0001
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 20 ether; // SEA

        _placeOrders(address(sea), address(0), amt, 10, 0, askPrice0, 0, gap, false, 500);

        assertEq(amt * 10, sea.balanceOf(address(exchange)));
        assertEq(0, usdc.balanceOf(address(exchange)));
        assertEq(initialSEAAmt - 10 * amt, sea.balanceOf(maker));

        (uint128 ethVol, uint128 fees) = Lens.calcAskOrderQuoteAmount(askPrice0, amt, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        vm.startPrank(taker);
        exchange.fillAskOrder{value: ethVol + fees}(gridOrderId, amt, amt, new bytes(0), 1);
        vm.stopPrank();

        // assertEq(fees / 2, exchange.protocolProfits(Currency.wrap(address(weth))));

        address third = address(0x300);

        vm.startPrank(third);
        vm.expectRevert();
        exchange.withdrawGridProfits(1, fees / 4, third, 0);
        vm.stopPrank();

        vm.startPrank(maker);
        exchange.withdrawGridProfits(1, fees / 4, maker, 0);
        vm.stopPrank();
        assertEq(fees / 4, weth.balanceOf(maker));

        vm.startPrank(maker);
        exchange.withdrawGridProfits(1, 0, maker, 1);
        vm.stopPrank();

        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 gapProfit = uint128((amt * gap) / PRICE_MULTIPLIER);
        assertEq(initialETHAmt + gapProfit + calcMakerFee(fees) - fees / 4, eth.balanceOf(maker));
    }
}
