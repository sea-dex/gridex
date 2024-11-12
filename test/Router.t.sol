// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {IWETH} from "../src/interfaces/IWETH.sol";
import {IPair} from "../src/interfaces/IPair.sol";
import {IGridEx} from "../src/interfaces/IGridEx.sol";
import {IGridExCallback} from "../src/interfaces/IGridExCallback.sol";
import {IOrderEvents} from "../src/interfaces/IOrderEvents.sol";

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {GridEx} from "../src/GridEx.sol";
import {Router} from "../src/Router.sol";
import {GridOrder} from "../src/GridOrder.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

contract RouterTest is Test {
    WETH public weth;
    GridEx public exchange;
    SEA public sea;
    USDC public usdc;
    Router public router;

    uint public constant BUY = 1;
    uint public constant SELL = 2;

    uint256 public constant PRICE_MULTIPLIER = 10 ** 29;

    function setUp() public {
        weth = new WETH();
        sea = new SEA();
        usdc = new USDC();
        exchange = new GridEx(address(weth), address(usdc));
        router = new Router(address(exchange));
    }

    function test_routerPlaceGridOrder() public {
        uint16 asks = 10;
        uint16 bids = 20;
        address other = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        sea.transfer(other, uint256(asks) * perBaseAmt);
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 askPrice0 = uint160((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        usdc.transfer(other, usdcAmt);

        vm.startPrank(other);
        sea.approve(address(router), uint256(asks) * perBaseAmt);
        usdc.approve(address(router), usdcAmt);
        IGridEx.GridOrderParam memory param = IGridEx.GridOrderParam({
            askOrderCount: asks,
            bidOrderCount: bids,
            baseAmount: perBaseAmt,
            askPrice0: askPrice0,
            bidPrice0: bidPrice0,
            askGap: gap,
            bidGap: gap,
            fee: 500,
            compound: false
        });
        router.placeGridOrders(address(sea), address(usdc), param);
        vm.stopPrank();
    }

    // side: 1: BUY; 2: SELL
    function placeOrder(
        uint side,
        address maker,
        address base,
        address quote,
        uint160 price0,
        uint160 gap,
        uint128 baseAmt,
        uint32 orderCount,
        uint32 fee
    ) internal {
        uint256 sumBaseAmt = baseAmt * orderCount;
        uint256 sumQuoteAmt = 0;

        if (side == BUY) {
            uint160 bidPrice = price0;
            for (uint32 i = 0; i < orderCount; ++i) {
                sumQuoteAmt += exchange.calcQuoteAmount(
                    baseAmt,
                    bidPrice,
                    false
                );
            }

            ERC20(quote).transfer(maker, sumQuoteAmt);
        } else {
            ERC20(base).transfer(maker, sumBaseAmt);
        }

        vm.startPrank(maker);
        if (side == BUY) {
            //
            ERC20(quote).approve(address(router), sumQuoteAmt);
        } else {
            ERC20(base).approve(address(router), sumBaseAmt);
        }

        if (side == BUY) {
            IGridEx.GridOrderParam memory param = IGridEx.GridOrderParam({
                askOrderCount: 0,
                bidOrderCount: orderCount,
                baseAmount: baseAmt,
                askPrice0: 0,
                bidPrice0: price0,
                askGap: 0,
                bidGap: gap,
                fee: fee,
                compound: false
            });
            router.placeGridOrders(address(base), address(quote), param);
        } else {
            IGridEx.GridOrderParam memory param = IGridEx.GridOrderParam({
                askOrderCount: orderCount,
                bidOrderCount: 0,
                baseAmount: baseAmt,
                askPrice0: price0,
                bidPrice0: 0,
                askGap: gap,
                bidGap: 0,
                fee: fee,
                compound: false
            });
            router.placeGridOrders(address(base), address(quote), param);
        }
        vm.stopPrank();
    }

    function test_fillAskOrder01() public {
        uint128 baseAmt = 100 * 10 ** 18;
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        uint160 askPrice0 = uint160((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        address maker = address(0x100);
        address taker = address(0x200);
        placeOrder(
            SELL,
            maker,
            address(sea),
            address(usdc),
            askPrice0,
            gap,
            baseAmt,
            10,
            100
        );

        uint128 usdcAmt = exchange.calcQuoteAmount(baseAmt, askPrice0, true);
        assertEq(usdcAmt, (askPrice0 * baseAmt) / PRICE_MULTIPLIER);

        uint128 fee = usdcAmt / 10000;
        usdcAmt += fee;
        usdc.transfer(taker, usdcAmt);
        vm.startPrank(taker);
        usdc.approve(address(router), usdcAmt);
        uint96 askOrderId = 0x800000000000000000000001;
        router.fillAskOrder(askOrderId, baseAmt, 0);
        vm.stopPrank();

        assertEq(sea.balanceOf(taker), baseAmt);
        GridEx.GridConfig memory gridConf = exchange.getGridConfig(1);
        assertEq(
            gridConf.profits,
            fee - (fee >> 2) + (gap * baseAmt) / PRICE_MULTIPLIER
        );

        GridEx.Order memory gridOrder = exchange.getGridOrder(askOrderId);
        assertEq(gridOrder.price, askPrice0);
        assertEq(gridOrder.revPrice, askPrice0 - gap);
        assertEq(gridOrder.amount, 0);
        assertEq(
            gridOrder.revAmount,
            ((askPrice0 - gap) * baseAmt) / PRICE_MULTIPLIER
        );

        assertEq(exchange.protocolFees(address(usdc)), fee >> 2);
    }

    function test_fillBidOrder01() public {
        uint128 baseAmt = 100 * 10 ** 18;
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        address maker = address(0x100);
        address taker = address(0x200);
        placeOrder(
            BUY,
            maker,
            address(sea),
            address(usdc),
            bidPrice0,
            gap,
            baseAmt,
            10,
            100
        );
        GridEx.Order memory gridOrder = exchange.getGridOrder(1);
        assertEq(gridOrder.price, bidPrice0);

        uint128 usdcAmt = exchange.calcQuoteAmount(baseAmt, bidPrice0, false);
        assertEq(usdcAmt, (bidPrice0 * baseAmt) / PRICE_MULTIPLIER);

        uint128 fee = usdcAmt / 10000;
        sea.transfer(taker, baseAmt);

        vm.startPrank(taker);
        sea.approve(address(router), baseAmt);
        uint96 bidOrderId = 0x1;
        router.fillBidOrder(bidOrderId, baseAmt, 0);
        vm.stopPrank();

        assertEq(usdc.balanceOf(taker), usdcAmt - fee);
        GridEx.GridConfig memory gridConf = exchange.getGridConfig(1);
        assertEq(gridConf.profits, fee - (fee >> 2));

        GridEx.Order memory gridOrder2 = exchange.getGridOrder(bidOrderId);
        assertEq(gridOrder2.price, bidPrice0);
        assertEq(gridOrder2.revPrice, bidPrice0 + gap);
        assertEq(gridOrder2.amount, 0);
        assertEq(gridOrder2.revAmount, baseAmt);

        assertEq(exchange.protocolFees(address(usdc)), fee >> 2);
    }
}
