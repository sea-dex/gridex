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

    function placeOrder() private {

    }

    function test_PlaceGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 100;
        uint16 bids = 100;
        address other = address(0x123);
        sea.transfer(other, uint256(asks) * 100 * (10 ** 18));
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint256 perBaseAmt = 100 * 10 ** 18;
        uint256 sellPrice0 = 50 * PRICE_MULTIPLIER/10/(10**12);
        uint256 buyPrice0 = 49 * PRICE_MULTIPLIER/10/(10**12);
        uint256 gap = 5*PRICE_MULTIPLIER/10000/(10**12);
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
        emit IPairEvents.GridOrderCreated(other, asks, bids, 1, pair.nextAskOrderId(), 1, sellPrice0, gap, 
        buyPrice0, gap, perBaseAmt, param.compound);
        pair.placeGridOrders(param);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(other));
        uint256 usdcUsed = 0;
        uint256 buyPrice = buyPrice0;
        for (uint i = 0; i < bids; i ++) {
            usdcUsed += pair.calcQuoteAmount2((perBaseAmt), (buyPrice));
            buyPrice -= gap;
        }
        console.log(usdcAmt - usdcUsed);
        assertEq(usdc.balanceOf(other), usdcAmt - usdcUsed);
    }

    function test_CancelGridOrder() public {
        // counter.increment();
        // assertEq(counter.number(), 1);
    }

    function test_FillAskGridOrder_01() public {
        // counter.increment();
        // assertEq(counter.number(), 1);
    }

    function test_FillAskGridOrder_02() public {
        // counter.increment();
        // assertEq(counter.number(), 1);
    }

    function test_FillAskGridOrder_03() public {
        // counter.increment();
        // assertEq(counter.number(), 1);
    }

    function test_FillBidGridOrder() public {
        // counter.increment();
        // assertEq(counter.number(), 1);
    }

    function testFuzz_SetNumber(uint256 x) public {
    }
}
