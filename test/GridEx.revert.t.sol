// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {GridExBaseTest} from "./GridExBase.t.sol";

contract GridExRevertTest is GridExBaseTest {
    // should revert if trade a canceled order
    function test_revertWhenTradeCanceledOrder() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        uint160 bidPrice0 = askPrice0 - gap;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 bidOrderId = 0x0000000000000000000000000000001;
        uint128 amt = 2 ether / 100; // ETH

        _placeOrders(
            address(0),
            address(usdc),
            amt,
            10,
            10,
            askPrice0,
            bidPrice0,
            gap,
            false,
            500
        );

        uint256 gridOrderId = toGridOrderId(1, orderId);
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 2);
        vm.stopPrank();

        // vm.startPrank(taker);
        // exchange.fillBidOrder{value: amt}(gridOrderId, amt, 0, new bytes(0), 1);
        // vm.stopPrank();

        vm.startPrank(taker);
        vm.expectRevert();
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 2);
        vm.stopPrank();

        vm.startPrank(maker);
        exchange.cancelGridOrders(msg.sender, gridOrderId, 2, 0);
        vm.stopPrank();

        vm.startPrank(taker);
        vm.expectRevert();
        exchange.fillAskOrder(gridOrderId, amt, amt, new bytes(0), 1);
        vm.stopPrank();

        uint256 gridOrderId2 = toGridOrderId(1, orderId + 1);
        vm.startPrank(taker);
        vm.expectRevert();
        exchange.fillAskOrder(gridOrderId2, amt, amt, new bytes(0), 1);
        vm.stopPrank();

        // bid order
        uint256 gridOrderId3 = toGridOrderId(1, bidOrderId);
        vm.startPrank(taker);
        exchange.fillBidOrder{value: amt / 2}(
            gridOrderId3,
            amt / 2,
            0,
            new bytes(0),
            1
        );
        vm.stopPrank();

        vm.startPrank(taker);
        vm.expectRevert();
        exchange.fillBidOrder{value: amt}(
            gridOrderId3,
            amt,
            amt / 2 + 1,
            new bytes(0),
            1
        );
        vm.stopPrank();

        vm.startPrank(maker);
        exchange.cancelGridOrders(msg.sender, gridOrderId3, 2, 0);
        vm.stopPrank();

        vm.startPrank(taker);
        vm.expectRevert();
        exchange.fillBidOrder{value: amt}(
            gridOrderId3,
            amt,
            0,
            new bytes(0),
            1
        );
        vm.stopPrank();

        vm.startPrank(taker);
        vm.expectRevert();
        exchange.fillBidOrder{value: amt}(
            gridOrderId3 + 1,
            amt,
            0,
            new bytes(0),
            1
        );
        vm.stopPrank();
    }

    // should revert if trade an oneshot order, which has been filled
    function test_revertWhenTradeOneshotOrder() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        uint160 bidPrice0 = askPrice0 - gap;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 bidOrderId = 0x0000000000000000000000000000001;
        uint128 amt = 2 ether / 100; // ETH

        _placeOneshotOrders(
            address(0),
            address(usdc),
            amt,
            10,
            10,
            askPrice0,
            bidPrice0,
            gap,
            false,
            500
        );

        uint256 gridOrderId = toGridOrderId(1, orderId);
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 2);
        vm.stopPrank();

        vm.startPrank(taker);
        vm.expectRevert();
        exchange.fillBidOrder{value: amt}(gridOrderId, amt, 0, new bytes(0), 1);
        vm.stopPrank();

        // bid order
        uint256 gridOrderId3 = toGridOrderId(1, bidOrderId);
        vm.startPrank(taker);
        exchange.fillBidOrder{value: amt}(
            gridOrderId3,
            amt,
            0,
            new bytes(0),
            1
        );
        vm.stopPrank();

        vm.startPrank(taker);
        vm.expectRevert();
        exchange.fillBidOrder{value: amt}(
            gridOrderId3,
            amt,
            0,
            new bytes(0),
            1
        );
        vm.stopPrank();
    }

    // should revert if withdraw more profits
    function test_revertInvalidWithdraw() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        uint160 bidPrice0 = askPrice0 - gap;
        uint128 orderId = 0x80000000000000000000000000000001;
        // uint128 bidOrderId = 0x0000000000000000000000000000001;
        uint128 amt = 2 ether / 100; // ETH

        // grid 1
        _placeOrdersBy(
            maker,
            address(0),
            address(usdc),
            amt,
            10,
            10,
            askPrice0,
            bidPrice0,
            gap,
            false,
            500
        );
        uint256 gridOrderId = toGridOrderId(1, orderId);
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 2);
        exchange.fillAskOrder(gridOrderId + 1, amt, 0, new bytes(0), 2);
        exchange.fillAskOrder(gridOrderId + 2, amt, 0, new bytes(0), 2);
        vm.stopPrank();

        // withdraw grid profits
        vm.startPrank(taker);
        vm.expectRevert();
        exchange.withdrawGridProfits(1, 0, taker, 2);
        vm.stopPrank();

        vm.startPrank(maker);
        exchange.withdrawGridProfits(1, 0, maker, 0);
        vm.expectRevert(); // NoProfits
        exchange.withdrawGridProfits(1, 0, maker, 0);
        vm.stopPrank();
    }

    // should revert if cancel NOT own order
    // should revert if cancel NOT own grid
    function test_revertWhenCancelOtherOrder() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        uint160 bidPrice0 = askPrice0 - gap;
        uint128 orderId = 0x80000000000000000000000000000001;
        uint128 bidOrderId = 0x0000000000000000000000000000001;
        uint128 amt = 2 ether / 100; // ETH

        // grid 1
        _placeOrdersBy(
            maker,
            address(0),
            address(usdc),
            amt,
            10,
            10,
            askPrice0,
            bidPrice0,
            gap,
            false,
            500
        );

        // grid 2
        _placeOrdersBy(
            maker,
            address(0),
            address(usdc),
            amt,
            10,
            10,
            askPrice0,
            bidPrice0,
            gap,
            false,
            500
        );

        // grid 3
        _placeOrdersBy(
            taker,
            address(0),
            address(usdc),
            amt,
            10,
            10,
            askPrice0,
            bidPrice0,
            gap,
            false,
            500
        );
        // grid 3
        _placeOrdersBy(
            taker,
            address(0),
            address(usdc),
            amt,
            10,
            10,
            askPrice0,
            bidPrice0,
            gap,
            false,
            500
        );

        uint256 gridOrderId = toGridOrderId(1, orderId);
        // revert if cancel NOT own order
        vm.startPrank(taker);
        vm.expectRevert();
        exchange.cancelGridOrders(taker, gridOrderId, 2, 0);
        vm.stopPrank();

        gridOrderId = toGridOrderId(2, orderId);
        vm.startPrank(maker);
        vm.expectRevert();
        exchange.cancelGridOrders(maker, gridOrderId, 1, 0);
        vm.stopPrank();

        gridOrderId = toGridOrderId(1, orderId + 10);
        vm.startPrank(maker);
        vm.expectRevert();
        exchange.cancelGridOrders(maker, gridOrderId, 1, 0);
        vm.stopPrank();

        gridOrderId = toGridOrderId(3, orderId + 20);
        vm.startPrank(maker);
        vm.expectRevert();
        exchange.cancelGridOrders(maker, gridOrderId, 1, 0);
        vm.stopPrank();

        // bid orders
        uint256 gridOrderId2 = toGridOrderId(1, bidOrderId);
        vm.startPrank(taker);
        vm.expectRevert();
        exchange.cancelGridOrders(taker, gridOrderId2, 2, 0);
        vm.stopPrank();

        gridOrderId2 = toGridOrderId(2, bidOrderId);
        vm.startPrank(maker);
        vm.expectRevert();
        exchange.cancelGridOrders(maker, gridOrderId2, 1, 0);
        vm.stopPrank();

        gridOrderId2 = toGridOrderId(1, bidOrderId + 10);
        vm.startPrank(maker);
        vm.expectRevert();
        exchange.cancelGridOrders(maker, gridOrderId2, 1, 0);
        vm.stopPrank();

        gridOrderId2 = toGridOrderId(3, bidOrderId + 20);
        vm.startPrank(maker);
        vm.expectRevert();
        exchange.cancelGridOrders(maker, gridOrderId2, 1, 0);
        vm.stopPrank();

        // should not cancel multiple times
        gridOrderId2 = toGridOrderId(3, bidOrderId + 20);
        vm.startPrank(taker);
        exchange.cancelGridOrders(taker, gridOrderId2, 1, 0);
        vm.expectRevert();
        exchange.cancelGridOrders(taker, gridOrderId2, 1, 0);
        vm.stopPrank();

        // cancel grid
        vm.startPrank(maker);
        vm.expectRevert();
        exchange.cancelGrid(maker, 3, 0);
        vm.stopPrank();

        vm.startPrank(maker);
        exchange.cancelGrid(maker, 1, 0);
        vm.expectRevert();
        exchange.cancelGrid(maker, 1, 0);
        vm.stopPrank();

        gridOrderId2 = toGridOrderId(2, bidOrderId + 10);
        vm.startPrank(maker);
        exchange.cancelGrid(maker, 2, 0);
        vm.expectRevert();
        exchange.cancelGridOrders(maker, gridOrderId2, 1, 0);
        vm.stopPrank();
    }

    // should revert if trade wrong gridId/orderId
    // should revert if flashloan not return
}
