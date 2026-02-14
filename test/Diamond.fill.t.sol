// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {CancelFacet} from "../src/facets/CancelFacet.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {ViewFacet} from "../src/facets/ViewFacet.sol";
import {GridExDiamondBaseTest} from "./GridExDiamondBase.t.sol";

/// @title Diamond Fill Test
/// @notice Basic fill tests using diamond architecture
contract DiamondFillTest is GridExDiamondBaseTest {
    function test_fillAskOrder() public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = askPrice0 / 20; // 0.0001
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 20000 ether; // SEA

        _placeOrders(address(sea), address(usdc), amt, 10, 0, askPrice0, askPrice0 - gap, gap, false, 500);

        assertEq(amt * 10, sea.balanceOf(exchange));
        assertEq(0, usdc.balanceOf(exchange));

        IGridOrder.GridConfig memory gridConf = ViewFacet(exchange).getGridConfig(1);
        assertEq(gridConf.pairId, 1);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        vm.startPrank(taker);
        TradeFacet(exchange).fillAskOrder(gridOrderId, amt, amt, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.OrderInfo memory info = ViewFacet(exchange).getGridOrder(gridOrderId);
        assertEq(info.amount, 0);
    }

    function test_fillBidOrder() public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = askPrice0 / 20; // 0.0001
        uint128 amt = 20000 ether; // SEA

        _placeOrders(address(sea), address(usdc), amt, 0, 10, askPrice0, askPrice0 - gap, gap, false, 500);

        uint128 bidOrderId = 1;
        uint256 gridOrderId = toGridOrderId(1, bidOrderId);

        vm.startPrank(taker);
        TradeFacet(exchange).fillBidOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.OrderInfo memory info = ViewFacet(exchange).getGridOrder(gridOrderId);
        // After filling a bid order, the quote amount should decrease
        assertEq(info.revAmount > 0, true); // base was added
    }

    function test_cancelGrid() public {
        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = askPrice0 / 20;
        uint128 amt = 20000 ether;

        _placeOrders(address(sea), address(usdc), amt, 10, 0, askPrice0, 0, gap, true, 500);
        assertEq(amt * 10, sea.balanceOf(exchange));

        vm.startPrank(maker);
        CancelFacet(exchange).cancelGrid(maker, 1, 0);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(exchange));
        assertEq(initialSEAAmt, sea.balanceOf(maker));
    }

    function test_pause_unpause() public {
        AdminFacet(exchange).pause();
        assertEq(ViewFacet(exchange).paused(), true);

        AdminFacet(exchange).unpause();
        assertEq(ViewFacet(exchange).paused(), false);
    }

    function test_viewFunctions() public view {
        assertEq(ViewFacet(exchange).owner(), address(this));
        assertEq(ViewFacet(exchange).vault(), vault);
        assertEq(ViewFacet(exchange).WETH(), address(weth));
        assertEq(ViewFacet(exchange).isStrategyWhitelisted(address(linear)), true);
    }
}
