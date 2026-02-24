// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {ViewFacet} from "../src/facets/ViewFacet.sol";
import {GridExDiamondBaseTest} from "./GridExDiamondBase.t.sol";

/// @title Diamond Upgrade Test
/// @notice Regression tests for swapping AdminFacet and TradeFacet selectors
contract DiamondUpgradeTest is GridExDiamondBaseTest {
    function _exposeFacetAddressView() internal {
        AdminFacet(exchange).setFacet(ViewFacet.facetAddress.selector, address(viewFacet));
    }

    function _replaceAdminFacet(address newAdmin) internal {
        bytes4[] memory selectors = new bytes4[](11);
        address[] memory facets = new address[](11);

        selectors[0] = AdminFacet.setFacet.selector;
        selectors[1] = AdminFacet.batchSetFacet.selector;
        selectors[2] = AdminFacet.setWETH.selector;
        selectors[3] = AdminFacet.setQuoteToken.selector;
        selectors[4] = AdminFacet.setStrategyWhitelist.selector;
        selectors[5] = AdminFacet.setOneshotProtocolFeeBps.selector;
        selectors[6] = AdminFacet.pause.selector;
        selectors[7] = AdminFacet.unpause.selector;
        selectors[8] = AdminFacet.rescueEth.selector;
        selectors[9] = AdminFacet.setFacetAllowlist.selector;
        selectors[10] = AdminFacet.transferOwnership.selector;

        for (uint256 i; i < selectors.length; i++) {
            facets[i] = newAdmin;
        }

        AdminFacet(exchange).batchSetFacet(selectors, facets);
    }

    function _replaceTradeFacet(address newTrade) internal {
        bytes4[] memory selectors = new bytes4[](6);
        address[] memory facets = new address[](6);

        selectors[0] = TradeFacet.placeGridOrders.selector;
        selectors[1] = TradeFacet.placeETHGridOrders.selector;
        selectors[2] = TradeFacet.fillAskOrder.selector;
        selectors[3] = TradeFacet.fillAskOrders.selector;
        selectors[4] = TradeFacet.fillBidOrder.selector;
        selectors[5] = TradeFacet.fillBidOrders.selector;

        for (uint256 i; i < selectors.length; i++) {
            facets[i] = newTrade;
        }

        AdminFacet(exchange).batchSetFacet(selectors, facets);
    }

    function test_replaceAdminFacet_selectorsReroutedAndWork() public {
        _exposeFacetAddressView();

        AdminFacet newAdmin = new AdminFacet();
        _replaceAdminFacet(address(newAdmin));

        assertEq(ViewFacet(exchange).facetAddress(AdminFacet.pause.selector), address(newAdmin));
        assertEq(ViewFacet(exchange).facetAddress(AdminFacet.setFacet.selector), address(newAdmin));
        assertEq(ViewFacet(exchange).facetAddress(AdminFacet.batchSetFacet.selector), address(newAdmin));

        AdminFacet(exchange).pause();
        assertEq(ViewFacet(exchange).paused(), true);
        AdminFacet(exchange).unpause();
        assertEq(ViewFacet(exchange).paused(), false);

        AdminFacet(exchange).setOneshotProtocolFeeBps(600);
        assertEq(ViewFacet(exchange).getOneshotProtocolFeeBps(), 600);
    }

    function test_replaceTradeFacet_selectorsReroutedAndFillStillWorks() public {
        _exposeFacetAddressView();

        TradeFacet newTrade = new TradeFacet();
        _replaceTradeFacet(address(newTrade));

        assertEq(ViewFacet(exchange).facetAddress(TradeFacet.placeGridOrders.selector), address(newTrade));
        assertEq(ViewFacet(exchange).facetAddress(TradeFacet.fillAskOrder.selector), address(newTrade));

        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint256 gap = askPrice0 / 20; // 0.0001
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 amt = 20000 ether;

        _placeOrders(address(sea), address(usdc), amt, 10, 0, askPrice0, askPrice0 - gap, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        vm.startPrank(taker);
        TradeFacet(exchange).fillAskOrder(gridOrderId, amt, amt, new bytes(0), 0);
        vm.stopPrank();

        IGridOrder.OrderInfo memory info = ViewFacet(exchange).getGridOrder(gridOrderId);
        assertEq(info.amount, 0);
    }

    function test_nonOwnerCannotSwitchFacet() public {
        address attacker = makeAddr("attacker");
        bytes4 selector = TradeFacet.fillAskOrder.selector;
        assertTrue(attacker != address(this));
        assertEq(ViewFacet(exchange).owner(), address(this));

        vm.startPrank(attacker);
        (bool okSetFacet, bytes memory retSetFacet) =
            exchange.call(abi.encodeWithSelector(AdminFacet.setFacet.selector, selector, address(new TradeFacet())));
        vm.stopPrank();
        assertFalse(okSetFacet);
        assertGe(retSetFacet.length, 4);
        assertEq(bytes4(retSetFacet), AdminFacet.NotOwner.selector);

        bytes4[] memory selectors = new bytes4[](1);
        address[] memory facets = new address[](1);
        selectors[0] = selector;
        facets[0] = address(new TradeFacet());

        vm.startPrank(attacker);
        (bool okBatchSetFacet, bytes memory retBatchSetFacet) =
            exchange.call(abi.encodeWithSelector(AdminFacet.batchSetFacet.selector, selectors, facets));
        vm.stopPrank();
        assertFalse(okBatchSetFacet);
        assertGe(retBatchSetFacet.length, 4);
        assertEq(bytes4(retBatchSetFacet), AdminFacet.NotOwner.selector);
    }
}
