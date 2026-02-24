// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {IPair} from "../src/interfaces/IPair.sol";
import {IProtocolErrors} from "../src/interfaces/IProtocolErrors.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {ViewFacet} from "../src/facets/ViewFacet.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {GridExDiamondBaseTest} from "./GridExDiamondBase.t.sol";

/// @title Diamond Upgrade Test
/// @notice Regression tests for swapping AdminFacet and TradeFacet selectors
contract DiamondUpgradeTest is GridExDiamondBaseTest {
    function _exposeFacetAddressView() internal {
        AdminFacet(exchange).setFacet(ViewFacet.facetAddress.selector, address(viewFacet));
    }

    function _exposeGetPairByIdView() internal {
        AdminFacet(exchange).setFacet(ViewFacet.getPairById.selector, address(viewFacet));
    }

    function _replaceAdminFacet(address newAdmin) internal {
        bytes4[] memory selectors = new bytes4[](10);
        address[] memory facets = new address[](10);

        selectors[0] = AdminFacet.setFacet.selector;
        selectors[1] = AdminFacet.batchSetFacet.selector;
        selectors[2] = AdminFacet.setWETH.selector;
        selectors[3] = AdminFacet.setQuoteToken.selector;
        selectors[4] = AdminFacet.setStrategyWhitelist.selector;
        selectors[5] = AdminFacet.setOneshotProtocolFeeBps.selector;
        selectors[6] = AdminFacet.pause.selector;
        selectors[7] = AdminFacet.unpause.selector;
        selectors[8] = AdminFacet.rescueEth.selector;
        selectors[9] = AdminFacet.transferOwnership.selector;

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
        // forge-lint: disable-next-line(unsafe-typecast)
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
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(retBatchSetFacet), AdminFacet.NotOwner.selector);
    }

    function test_batchSetFacet_revertOnLengthMismatch() public {
        bytes4[] memory selectors = new bytes4[](1);
        address[] memory facets = new address[](2);
        selectors[0] = TradeFacet.fillAskOrder.selector;
        facets[0] = address(new TradeFacet());
        facets[1] = address(new TradeFacet());

        vm.expectRevert(bytes("Length mismatch"));
        AdminFacet(exchange).batchSetFacet(selectors, facets);
    }

    function test_transferOwnership_thenNewOwnerCanUpgrade() public {
        _exposeFacetAddressView();

        address newOwner = makeAddr("new-owner");
        AdminFacet(exchange).transferOwnership(newOwner);
        assertEq(ViewFacet(exchange).owner(), newOwner);

        vm.expectRevert(AdminFacet.NotOwner.selector);
        AdminFacet(exchange).pause();

        vm.startPrank(newOwner);
        AdminFacet(exchange).pause();
        vm.stopPrank();
        assertEq(ViewFacet(exchange).paused(), true);

        vm.startPrank(newOwner);
        AdminFacet(exchange).setFacet(TradeFacet.fillAskOrder.selector, address(new TradeFacet()));
        vm.stopPrank();
        assertEq(ViewFacet(exchange).facetAddress(TradeFacet.fillAskOrder.selector) != address(0), true);
    }

    function test_rescueEth_ownerOnlyAndTransfer() public {
        address receiver = makeAddr("receiver");
        vm.deal(exchange, 1 ether);

        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);
        vm.expectRevert(AdminFacet.NotOwner.selector);
        AdminFacet(exchange).rescueEth(receiver, 0.1 ether);
        vm.stopPrank();

        uint256 before = receiver.balance;
        AdminFacet(exchange).rescueEth(receiver, 0.25 ether);
        assertEq(receiver.balance - before, 0.25 ether);
    }

    function test_fallback_revertOnUnknownSelector() public {
        (bool ok, bytes memory ret) = exchange.call(abi.encodeWithSelector(bytes4(keccak256("unknownSelector()"))));
        assertFalse(ok);
        assertGe(ret.length, 4);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(ret), bytes4(keccak256("FacetNotFound()")));
    }

    function test_viewPairQueries_consistencyAndInvalidPairRevert() public {
        _exposeGetPairByIdView();

        uint256 askPrice0 = uint256(PRICE_MULTIPLIER / 500 / (10 ** 12));
        uint256 gap = askPrice0 / 20;
        uint128 amt = 1000 ether;
        _placeOrders(address(sea), address(usdc), amt, 1, 0, askPrice0, 0, gap, false, 500);

        uint64 pairId = ViewFacet(exchange).getPairIdByTokens(Currency.wrap(address(sea)), Currency.wrap(address(usdc)));
        (Currency base, Currency quote) = ViewFacet(exchange).getPairTokens(pairId);
        (Currency base2, Currency quote2, uint64 id2) = ViewFacet(exchange).getPairById(pairId);
        assertEq(Currency.unwrap(base), address(sea));
        assertEq(Currency.unwrap(quote), address(usdc));
        assertEq(Currency.unwrap(base2), address(sea));
        assertEq(Currency.unwrap(quote2), address(usdc));
        assertEq(id2, pairId);

        vm.expectRevert(IPair.InvalidPairId.selector);
        ViewFacet(exchange).getPairTokens(type(uint64).max);
    }

    function test_setFacet_revertWhenFacetHasNoCode() public {
        vm.expectRevert(IProtocolErrors.InvalidAddress.selector);
        AdminFacet(exchange).setFacet(TradeFacet.fillAskOrder.selector, address(0xBEEF));
    }

    function test_batchSetFacet_revertWhenAnyFacetHasNoCode() public {
        bytes4[] memory selectors = new bytes4[](2);
        address[] memory facets = new address[](2);
        selectors[0] = TradeFacet.fillAskOrder.selector;
        facets[0] = address(new TradeFacet());
        selectors[1] = TradeFacet.fillBidOrder.selector;
        facets[1] = address(0xCAFE);

        vm.expectRevert(IProtocolErrors.InvalidAddress.selector);
        AdminFacet(exchange).batchSetFacet(selectors, facets);
    }
}
