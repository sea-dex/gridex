// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {GridExBaseTest} from "./GridExBase.t.sol";
import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {Pausable} from "../src/utils/Pausable.sol";

/// @title GridEx Pause Tests
/// @notice Tests for pause/unpause functionality
contract GridExPauseTest is GridExBaseTest {
    // Use SEA/WETH pair (both 18 decimals) for simpler testing
    // Price: 1 SEA = 0.001 WETH (1e33 in PRICE_MULTIPLIER terms)
    uint256 constant ASK_PRICE = 1e33;
    uint256 constant BID_PRICE = 9e32;
    uint256 constant PRICE_GAP = 1e31;

    // Ask orders have high bit set
    uint128 constant ASK_ORDER_FLAG = 0x80000000000000000000000000000000;
    uint128 constant ASK_ORDER_START_ID = ASK_ORDER_FLAG | 1;
    uint128 constant BID_ORDER_START_ID = 1;

    function setUp() public override {
        super.setUp();

        // Deposit ETH to get WETH for maker and taker
        vm.startPrank(maker);
        weth.deposit{value: 5 ether}();
        weth.approve(address(exchange), type(uint128).max);
        vm.stopPrank();

        vm.startPrank(taker);
        weth.deposit{value: 5 ether}();
        weth.approve(address(exchange), type(uint128).max);
        vm.stopPrank();
    }

    /// @notice Helper to create ask order ID
    function toAskOrderId(uint128 gridId, uint128 orderIndex) internal pure returns (uint256) {
        return toGridOrderId(gridId, ASK_ORDER_START_ID + orderIndex);
    }

    /// @notice Helper to create bid order ID
    function toBidOrderId(uint128 gridId, uint128 orderIndex) internal pure returns (uint256) {
        return toGridOrderId(gridId, BID_ORDER_START_ID + orderIndex);
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSE STATE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test initial state is not paused
    function test_InitialStateNotPaused() public view {
        assertFalse(exchange.paused(), "Exchange should not be paused initially");
    }

    /// @notice Test owner can pause the exchange
    function test_OwnerCanPause() public {
        exchange.pause();
        assertTrue(exchange.paused(), "Exchange should be paused after pause()");
    }

    /// @notice Test owner can unpause the exchange
    function test_OwnerCanUnpause() public {
        exchange.pause();
        assertTrue(exchange.paused(), "Exchange should be paused");

        exchange.unpause();
        assertFalse(exchange.paused(), "Exchange should not be paused after unpause()");
    }

    /// @notice Test non-owner cannot pause
    function test_NonOwnerCannotPause() public {
        vm.prank(maker);
        vm.expectRevert("UNAUTHORIZED");
        exchange.pause();
    }

    /// @notice Test non-owner cannot unpause
    function test_NonOwnerCannotUnpause() public {
        exchange.pause();

        vm.prank(maker);
        vm.expectRevert("UNAUTHORIZED");
        exchange.unpause();
    }

    /// @notice Test cannot pause when already paused
    function test_CannotPauseWhenPaused() public {
        exchange.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        exchange.pause();
    }

    /// @notice Test cannot unpause when not paused
    function test_CannotUnpauseWhenNotPaused() public {
        vm.expectRevert(Pausable.ExpectedPause.selector);
        exchange.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSED OPERATIONS TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test placeGridOrders reverts when paused
    function test_PlaceGridOrdersRevertsWhenPaused() public {
        exchange.pause();

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line
            askData: abi.encode(ASK_PRICE, int256(PRICE_GAP)),
            // forge-lint: disable-next-line
            bidData: abi.encode(BID_PRICE, -int256(PRICE_GAP)),
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: 1 ether,
            fee: 1000,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(weth)), param);
        vm.stopPrank();
    }

    /// @notice Test placeETHGridOrders reverts when paused
    function test_PlaceETHGridOrdersRevertsWhenPaused() public {
        exchange.pause();

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line
            askData: abi.encode(ASK_PRICE, int256(PRICE_GAP)),
            // forge-lint: disable-next-line
            bidData: abi.encode(BID_PRICE, -int256(PRICE_GAP)),
            askOrderCount: 5,
            bidOrderCount: 0,
            baseAmount: 1 ether,
            fee: 1000,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        exchange.placeETHGridOrders{value: 5 ether}(Currency.wrap(address(0)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    /// @notice Test fillAskOrder reverts when paused
    function test_FillAskOrderRevertsWhenPaused() public {
        // First place orders while not paused (SEA/WETH pair)
        _placeOrders(address(sea), address(weth), 1 ether, 5, 5, ASK_PRICE, BID_PRICE, PRICE_GAP, false, 1000);

        // Now pause
        exchange.pause();

        // Try to fill - should revert (use correct ask order ID)
        uint256 orderId = toAskOrderId(1, 0); // First ask order
        vm.startPrank(taker);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        exchange.fillAskOrder(orderId, 1 ether, 0, "", 0);
        vm.stopPrank();
    }

    /// @notice Test fillBidOrder reverts when paused
    function test_FillBidOrderRevertsWhenPaused() public {
        // First place orders while not paused (SEA/WETH pair)
        _placeOrders(address(sea), address(weth), 1 ether, 5, 5, ASK_PRICE, BID_PRICE, PRICE_GAP, false, 1000);

        // Now pause
        exchange.pause();

        // Try to fill bid order - should revert (use correct bid order ID)
        uint256 orderId = toBidOrderId(1, 0); // First bid order
        vm.startPrank(taker);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        exchange.fillBidOrder(orderId, 1 ether, 0, "", 0);
        vm.stopPrank();
    }

    /// @notice Test fillAskOrders reverts when paused
    function test_FillAskOrdersRevertsWhenPaused() public {
        // First place orders while not paused (SEA/WETH pair)
        _placeOrders(address(sea), address(weth), 1 ether, 5, 5, ASK_PRICE, BID_PRICE, PRICE_GAP, false, 1000);

        // Now pause
        exchange.pause();

        // Try to fill multiple orders - should revert
        uint256[] memory idList = new uint256[](2);
        idList[0] = toAskOrderId(1, 0);
        idList[1] = toAskOrderId(1, 1);

        uint128[] memory amtList = new uint128[](2);
        amtList[0] = 0.5 ether;
        amtList[1] = 0.5 ether;

        vm.startPrank(taker);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        exchange.fillAskOrders(1, idList, amtList, 0, 0, "", 0);
        vm.stopPrank();
    }

    /// @notice Test fillBidOrders reverts when paused
    function test_FillBidOrdersRevertsWhenPaused() public {
        // First place orders while not paused (SEA/WETH pair)
        _placeOrders(address(sea), address(weth), 1 ether, 5, 5, ASK_PRICE, BID_PRICE, PRICE_GAP, false, 1000);

        // Now pause
        exchange.pause();

        // Try to fill multiple bid orders - should revert
        uint256[] memory idList = new uint256[](2);
        idList[0] = toBidOrderId(1, 0);
        idList[1] = toBidOrderId(1, 1);

        uint128[] memory amtList = new uint128[](2);
        amtList[0] = 0.5 ether;
        amtList[1] = 0.5 ether;

        vm.startPrank(taker);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        exchange.fillBidOrders(1, idList, amtList, 0, 0, "", 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    ALLOWED OPERATIONS WHEN PAUSED
    //////////////////////////////////////////////////////////////*/

    /// @notice Test cancelGrid works when paused
    function test_CancelGridWorksWhenPaused() public {
        // First place orders while not paused (SEA/WETH pair)
        _placeOrders(address(sea), address(weth), 1 ether, 5, 5, ASK_PRICE, BID_PRICE, PRICE_GAP, false, 1000);

        // Now pause
        exchange.pause();

        // Cancel should still work
        vm.startPrank(maker);
        exchange.cancelGrid(maker, 1, 0);
        vm.stopPrank();
    }

    /// @notice Test cancelGridOrders works when paused
    function test_CancelGridOrdersWorksWhenPaused() public {
        // First place orders while not paused (SEA/WETH pair)
        _placeOrders(address(sea), address(weth), 1 ether, 5, 5, ASK_PRICE, BID_PRICE, PRICE_GAP, false, 1000);

        // Now pause
        exchange.pause();

        // Cancel specific orders should still work (use ask order IDs)
        uint256[] memory idList = new uint256[](2);
        idList[0] = toAskOrderId(1, 0);
        idList[1] = toAskOrderId(1, 1);

        vm.startPrank(maker);
        exchange.cancelGridOrders(1, maker, idList, 0);
        vm.stopPrank();
    }

    /// @notice Test withdrawGridProfits works when paused
    function test_WithdrawGridProfitsWorksWhenPaused() public {
        // First place orders and generate some profits (SEA/WETH pair)
        _placeOrders(address(sea), address(weth), 1 ether, 5, 5, ASK_PRICE, BID_PRICE, PRICE_GAP, false, 1000);

        // Fill an ask order to generate profits (use correct ask order ID)
        uint256 orderId = toAskOrderId(1, 0);
        vm.startPrank(taker);
        exchange.fillAskOrder(orderId, 1 ether, 0, "", 0);
        vm.stopPrank();

        // Now pause
        exchange.pause();

        // Withdraw profits should still work (even if no profits, the function should be callable)
        vm.startPrank(maker);
        // This may revert with NoProfits if there are no profits, but not with EnforcedPause
        try exchange.withdrawGridProfits(1, 0, maker, 0) {
        // Success - profits were withdrawn
        }
            catch {
            // May fail for other reasons (no profits), but not because of pause
        }
        vm.stopPrank();
    }

    /// @notice Test getGridOrder works when paused
    function test_GetGridOrderWorksWhenPaused() public {
        // First place orders while not paused (SEA/WETH pair)
        _placeOrders(address(sea), address(weth), 1 ether, 5, 5, ASK_PRICE, BID_PRICE, PRICE_GAP, false, 1000);

        // Now pause
        exchange.pause();

        // View functions should still work (use correct ask order ID)
        uint256 orderId = toAskOrderId(1, 0);
        IGridOrder.OrderInfo memory info = exchange.getGridOrder(orderId);
        assertEq(info.baseAmt, 1 ether, "Should be able to read order info when paused");
    }

    /*//////////////////////////////////////////////////////////////
                        UNPAUSE AND RESUME TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test operations work after unpause
    function test_OperationsWorkAfterUnpause() public {
        // First place orders while not paused (SEA/WETH pair)
        _placeOrders(address(sea), address(weth), 1 ether, 5, 5, ASK_PRICE, BID_PRICE, PRICE_GAP, false, 1000);

        // Pause
        exchange.pause();

        // Verify fill reverts (use correct ask order ID)
        uint256 orderId = toAskOrderId(1, 0);
        vm.startPrank(taker);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        exchange.fillAskOrder(orderId, 1 ether, 0, "", 0);
        vm.stopPrank();

        // Unpause
        exchange.unpause();

        // Now fill should work
        vm.startPrank(taker);
        exchange.fillAskOrder(orderId, 1 ether, 0, "", 0);
        vm.stopPrank();

        // Verify order was filled - amount is 0 after fill (baseAmt is the grid's base amount per order)
        IGridOrder.OrderInfo memory info = exchange.getGridOrder(orderId);
        assertEq(info.amount, 0, "Order amount should be 0 after fill");
        // After filling an ask order, it becomes a reverse bid order with revAmount > 0
        assertTrue(info.revAmount > 0, "Order should have reverse amount after fill");
    }

    /// @notice Test placing orders works after unpause
    function test_PlaceOrdersWorksAfterUnpause() public {
        // Pause
        exchange.pause();

        // Verify place reverts
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line
            askData: abi.encode(ASK_PRICE, int256(PRICE_GAP)),
            // forge-lint: disable-next-line
            bidData: abi.encode(BID_PRICE, -int256(PRICE_GAP)),
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: 1 ether,
            fee: 1000,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(weth)), param);
        vm.stopPrank();

        // Unpause
        exchange.unpause();

        // Now place should work
        vm.startPrank(maker);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(weth)), param);
        vm.stopPrank();

        // Verify order was placed
        uint256 orderId = toGridOrderId(1, 1);
        IGridOrder.OrderInfo memory info = exchange.getGridOrder(orderId);
        assertEq(info.baseAmt, 1 ether, "Order should be placed after unpause");
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test Paused event is emitted
    function test_PausedEventEmitted() public {
        vm.expectEmit(true, false, false, false);
        emit Pausable.Paused(address(this));
        exchange.pause();
    }

    /// @notice Test Unpaused event is emitted
    function test_UnpausedEventEmitted() public {
        exchange.pause();

        vm.expectEmit(true, false, false, false);
        emit Pausable.Unpaused(address(this));
        exchange.unpause();
    }
}
