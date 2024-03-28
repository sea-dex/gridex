// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {IPair} from "../src/interfaces/IPair.sol";
import {IPairEvents} from "../src/interfaces/IPairEvents.sol";

import {Test, console} from "forge-std/Test.sol";
import {Pair} from "../src/Pair.sol";
import {Factory} from "../src/Factory.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

contract PairTest is Test {
    Pair public pair;
    Factory public factory;
    SEA public sea;
    USDC public usdc;

    uint256 constant PRICE_MULTIPLIER = 10 ** 30;

    function setUp() public {
        factory = new Factory();
        sea = new SEA();
        usdc = new USDC();

        factory.setQuoteToken(address(usdc), 200);

        address seaUSDC = factory.createPair(address(sea), address(usdc), 500);
        pair = Pair(payable(seaUSDC));
    }

    function placeOrder() private {}

    function test_PlaceGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 100;
        uint16 bids = 100;
        address other = address(0x123);
        sea.transfer(other, uint256(asks) * 100 * (10 ** 18));
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint256 perBaseAmt = 100 * 10 ** 18;
        uint256 sellPrice0 = (50 * PRICE_MULTIPLIER) / 10 / (10 ** 12);
        uint256 buyPrice0 = (49 * PRICE_MULTIPLIER) / 10 / (10 ** 12);
        uint256 gap = (5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12);
        usdc.transfer(other, usdcAmt);

        vm.startPrank(other);
        Pair.GridOrderParam memory param = Pair.GridOrderParam({
            asks: asks,
            bids: bids,
            baseAmount: uint96(perBaseAmt),
            sellPrice0: sellPrice0,
            buyPrice0: buyPrice0,
            sellGap: gap,
            buyGap: gap,
            compound: false
        });
        sea.approve(address(pair), type(uint96).max);
        usdc.approve(address(pair), type(uint96).max);
        vm.expectEmit(true, true, true, true);
        emit IPairEvents.GridOrderCreated(
            other,
            asks,
            bids,
            1,
            0x8000000000000001 + uint64(asks),
            bids + 1,
            sellPrice0,
            gap,
            buyPrice0,
            gap,
            perBaseAmt,
            param.compound
        );
        pair.placeGridOrders(param);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(other));
        uint256 usdcUsed = 0;
        uint256 buyPrice = buyPrice0;
        for (uint i = 0; i < bids; i++) {
            usdcUsed += pair.calcQuoteAmount((perBaseAmt), (buyPrice));
            buyPrice -= gap;
        }
        console.log(usdcAmt - usdcUsed);
        assertEq(usdc.balanceOf(other), usdcAmt - usdcUsed);
    }

    function test_CancelGridOrder() public {
        // counter.increment();
        // assertEq(counter.number(), 1);
    }

    // not compound grid
    function test_FillAskGridOrder_01() public {
        address maker = address(0x111);
        address taker = address(0x333);
        uint16 asks = 1;

        uint256 perBaseAmt = 100 * 10 ** 18;
        uint256 sellPrice0 = (50 * PRICE_MULTIPLIER) / 10 / (10 ** 12);
        uint256 usdcAmt = (10 * uint256(asks) * perBaseAmt * sellPrice0) /
            PRICE_MULTIPLIER;

        uint256 gap = (5 * PRICE_MULTIPLIER) / 100 / (10 ** 12);
        sea.transfer(maker, uint256(asks) * 100 * (10 ** 18));
        usdc.transfer(taker, usdcAmt);

        // place order
        vm.startPrank(maker);
        Pair.GridOrderParam memory param = Pair.GridOrderParam({
            asks: asks,
            bids: 0,
            baseAmount: uint96(perBaseAmt),
            sellPrice0: sellPrice0,
            buyPrice0: sellPrice0 - gap,
            sellGap: gap,
            buyGap: gap,
            compound: false
        });
        sea.approve(address(pair), type(uint96).max);
        pair.placeGridOrders(param);
        vm.stopPrank();

        // fill order
        vm.startPrank(taker);
        usdc.approve(address(pair), type(uint96).max);
        uint64 id = 0x8000000000000001; // first ask grid order
        pair.fillAskOrders(id, perBaseAmt, 0, 0);
        vm.stopPrank();

        Pair.Order memory order = pair.getGridOrder(id);
        assertEq(order.amount, 0);
        assertEq(sea.balanceOf(taker), perBaseAmt);
        assertEq(sea.balanceOf(address(pair)), 0);

        {
            uint256 filledVol = (perBaseAmt * (sellPrice0)) / PRICE_MULTIPLIER;
            uint256 fee = (filledVol * 500) / 1000000;
            uint256 quota = (perBaseAmt * (sellPrice0 - gap)) /
                PRICE_MULTIPLIER;
            uint8 feeProtocol = pair.feeProtocol();
            assertEq(order.revAmount, quota);
            assertEq(pair.protocolFees(), fee / feeProtocol);
            assertEq(pair.getGridProfits(1), filledVol - quota  + fee - fee/feeProtocol);
        }

        uint256 usdcNow = usdc.balanceOf(taker) + pair.getGridProfits(1) + pair.protocolFees() + order.revAmount;
        assertEq(usdcAmt, usdcNow);
        assertEq(usdcAmt, usdc.balanceOf(taker) + usdc.balanceOf(address(pair)));
    }

    function test_FillAskGridOrder_02() public {
        address maker = address(0x111);
        address taker = address(0x333);
        uint16 asks = 1;

        uint256 perBaseAmt = 100 * 10 ** 18;
        uint256 sellPrice0 = (50 * PRICE_MULTIPLIER) / 10 / (10 ** 12);
        uint256 usdcAmt = (10 * uint256(asks) * perBaseAmt * sellPrice0) /
            PRICE_MULTIPLIER;

        uint256 gap = (5 * PRICE_MULTIPLIER) / 100 / (10 ** 12);
        sea.transfer(maker, uint256(asks) * 100 * (10 ** 18));
        usdc.transfer(taker, usdcAmt);

        // place order
        vm.startPrank(maker);
        Pair.GridOrderParam memory param = Pair.GridOrderParam({
            asks: asks,
            bids: 0,
            baseAmount: uint96(perBaseAmt),
            sellPrice0: sellPrice0,
            buyPrice0: sellPrice0 - gap,
            sellGap: gap,
            buyGap: gap,
            compound: true
        });
        sea.approve(address(pair), type(uint96).max);
        pair.placeGridOrders(param);
        vm.stopPrank();

        // fill order
        vm.startPrank(taker);
        usdc.approve(address(pair), type(uint96).max);
        uint64 id = 0x8000000000000001; // first ask grid order
        pair.fillAskOrders(id, perBaseAmt, 0, 0);
        vm.stopPrank();

        Pair.Order memory order = pair.getGridOrder(id);
        assertEq(order.amount, 0);
        assertEq(sea.balanceOf(taker), perBaseAmt);
        assertEq(sea.balanceOf(address(pair)), 0);

        {
            uint256 filledVol = (perBaseAmt * (sellPrice0)) / PRICE_MULTIPLIER;
            uint256 fee = (filledVol * 500) / 1000000;
            uint8 feeProtocol = pair.feeProtocol();
            assertEq(order.revAmount, filledVol + fee - fee/feeProtocol);
            assertEq(pair.protocolFees(), fee / feeProtocol);
            assertEq(pair.getGridProfits(1), 0);
        }

        uint256 usdcNow = usdc.balanceOf(taker) + pair.getGridProfits(1) + pair.protocolFees() + order.revAmount;
        assertEq(usdcAmt, usdcNow);
        assertEq(usdcAmt, usdc.balanceOf(taker) + usdc.balanceOf(address(pair)));
    }

    function test_FillAskGridOrder_03() public {
        // counter.increment();
        // assertEq(counter.number(), 1);
    }

    function test_FillBidGridOrder_01() public {
        address maker = address(0x111);
        address taker = address(0x333);
        uint16 bids = 1;

        uint256 perBaseAmt = 100 * 10 ** 18;
        uint256 buyPrice0 = (50 * PRICE_MULTIPLIER) / 10 / (10 ** 12);
        uint256 usdcAmt = (uint256(bids) * perBaseAmt * buyPrice0) /
            PRICE_MULTIPLIER;

        uint256 gap = (5 * PRICE_MULTIPLIER) / 100 / (10 ** 12);
        sea.transfer(taker, perBaseAmt);
        usdc.transfer(maker, usdcAmt);

        // place order
        vm.startPrank(maker);
        Pair.GridOrderParam memory param = Pair.GridOrderParam({
            asks: 0,
            bids: bids,
            baseAmount: uint96(perBaseAmt),
            sellPrice0: buyPrice0 + gap,
            buyPrice0: buyPrice0,
            sellGap: gap,
            buyGap: gap,
            compound: false
        });
        usdc.approve(address(pair), type(uint96).max);
        pair.placeGridOrders(param);
        vm.stopPrank();

        // fill order
        vm.startPrank(taker);
        sea.approve(address(pair), type(uint96).max);
        uint64 id = 1; // first ask grid order
        pair.fillBidOrders(id, perBaseAmt, 0, 0);
        vm.stopPrank();

        Pair.Order memory order = pair.getGridOrder(id);
        assertEq(order.amount, 0);
        assertEq(sea.balanceOf(taker), 0);
        assertEq(sea.balanceOf(address(pair)), perBaseAmt);

        {
            uint256 filledVol = (perBaseAmt * (buyPrice0)) / PRICE_MULTIPLIER;
            uint256 fee = (filledVol * uint256(pair.fee())) / 1000000;
            uint8 feeProtocol = pair.feeProtocol();
            assertEq(order.revAmount, perBaseAmt);
            assertEq(pair.protocolFees(), fee / feeProtocol);
            assertEq(pair.getGridProfits(1), fee - fee/feeProtocol);
        }

        uint256 usdcNow = usdc.balanceOf(taker) + pair.getGridProfits(1) + pair.protocolFees() + order.amount;
        assertEq(usdcAmt, usdcNow);
        assertEq(usdcAmt, usdc.balanceOf(taker) + usdc.balanceOf(address(pair)));
    }

    // compound: true
    function test_FillBidGridOrder_02() public {
        address maker = address(0x111);
        address taker = address(0x333);
        uint16 bids = 1;

        uint256 perBaseAmt = 100 * 10 ** 18;
        uint256 buyPrice0 = (50 * PRICE_MULTIPLIER) / 10 / (10 ** 12);
        uint256 usdcAmt = (uint256(bids) * perBaseAmt * buyPrice0) /
            PRICE_MULTIPLIER;

        uint256 gap = (5 * PRICE_MULTIPLIER) / 100 / (10 ** 12);
        sea.transfer(taker, perBaseAmt);
        usdc.transfer(maker, usdcAmt);

        // place order
        vm.startPrank(maker);
        Pair.GridOrderParam memory param = Pair.GridOrderParam({
            asks: 0,
            bids: bids,
            baseAmount: uint96(perBaseAmt),
            sellPrice0: buyPrice0 + gap,
            buyPrice0: buyPrice0,
            sellGap: gap,
            buyGap: gap,
            compound: true
        });
        usdc.approve(address(pair), type(uint96).max);
        pair.placeGridOrders(param);
        vm.stopPrank();

        // fill order
        vm.startPrank(taker);
        sea.approve(address(pair), type(uint96).max);
        uint64 id = 1; // first ask grid order
        pair.fillBidOrders(id, perBaseAmt, 0, 0);
        vm.stopPrank();

        Pair.Order memory order = pair.getGridOrder(id);
        assertEq(sea.balanceOf(taker), 0);
        assertEq(sea.balanceOf(address(pair)), perBaseAmt);

        {
            uint256 filledVol = (perBaseAmt * (buyPrice0)) / PRICE_MULTIPLIER;
            uint256 fee = (filledVol * uint256(pair.fee())) / 1000000;
            uint8 feeProtocol = pair.feeProtocol();
            assertEq(order.revAmount, perBaseAmt);
            assertEq(pair.protocolFees(), fee / feeProtocol);
            assertEq(pair.getGridProfits(1), 0);
            assertEq(order.amount, fee - fee/feeProtocol); // 
        }

        uint256 usdcNow = usdc.balanceOf(taker) + pair.getGridProfits(1) + pair.protocolFees() + order.amount;
        assertEq(usdcAmt, usdcNow);
        assertEq(usdcAmt, usdc.balanceOf(taker) + usdc.balanceOf(address(pair)));
    }

    function testFuzz_SetNumber(uint256 x) public {}
}
