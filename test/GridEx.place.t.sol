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

contract GridExPlaceTest is Test {
    WETH public weth;
    GridEx public exchange;
    SEA public sea;
    USDC public usdc;

    uint256 public constant PRICE_MULTIPLIER = 10 ** 29;

    function setUp() public {
        weth = new WETH();
        sea = new SEA();
        usdc = new USDC();
        exchange = new GridEx(address(weth), address(usdc));
    }

    function test_PlaceAskGridOrder() public {
        uint16 asks = 13;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 baseAmt = uint256(asks) * perBaseAmt;
        uint160 askPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        address maker = address(0x123);

        sea.transfer(maker, baseAmt);

        IGridEx.GridOrderParam memory param = IGridEx.GridOrderParam({
            askOrderCount: asks,
            bidOrderCount: 0,
            baseAmount: perBaseAmt,
            askPrice0: askPrice0,
            bidPrice0: 0,
            askGap: gap,
            bidGap: 0,
            fee: 500,
            compound: false
        });

        vm.startPrank(maker);
        sea.approve(address(exchange), type(uint128).max);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        assertEq(sea.balanceOf(maker), 0);
        assertEq(uint256(asks) * perBaseAmt, sea.balanceOf(address(exchange)));
    }

    function test_PlaceETHBaseAskGridOrder() public {
        uint16 asks = 13;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 baseAmt = uint256(asks) * perBaseAmt;
        uint160 askPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        address maker = address(0x123);

        vm.deal(maker, baseAmt);

        IGridEx.GridOrderParam memory param = IGridEx.GridOrderParam({
            askOrderCount: asks,
            bidOrderCount: 0,
            baseAmount: perBaseAmt,
            askPrice0: askPrice0,
            bidPrice0: 0,
            askGap: gap,
            bidGap: 0,
            fee: 500,
            compound: false
        });

        vm.startPrank(maker);
        exchange.placeETHGridOrders{value: baseAmt}(Currency.wrap(address(0)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        assertEq(uint256(asks) * perBaseAmt, weth.balanceOf(address(exchange)));
        assertEq(0, Currency.wrap(address(0)).balanceOf(address(exchange)));
        assertEq(Currency.wrap(address(0)).balanceOf(maker), 0);
    }

    function test_PlaceBidGridOrder() public {
        uint16 bids = 10;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        address maker = address(0x123);

        usdc.transfer(maker, usdcAmt);

        IGridEx.GridOrderParam memory param = IGridEx.GridOrderParam({
            askOrderCount: 0,
            bidOrderCount: bids,
            baseAmount: perBaseAmt,
            askPrice0: 0,
            bidPrice0: bidPrice0,
            askGap: 0,
            bidGap: gap,
            fee: 500,
            compound: false
        });

        vm.startPrank(maker);
        usdc.approve(address(exchange), type(uint128).max);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        assertEq(usdc.balanceOf(maker) > 0, true);
        assertEq(usdcAmt > usdc.balanceOf(address(exchange)), true);
        assertEq(usdcAmt, usdc.balanceOf(maker) + usdc.balanceOf(address(exchange)));
    }

    function test_PlaceETHQuoteBidGridOrder() public {
        uint16 bids = 10;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        address maker = address(0x123);

        (, uint128 ethAmt) = exchange.calcGridAmount(perBaseAmt, bidPrice0, gap, 0, bids);
        vm.deal(maker, ethAmt);

        IGridEx.GridOrderParam memory param = IGridEx.GridOrderParam({
            askOrderCount: 0,
            bidOrderCount: bids,
            baseAmount: perBaseAmt,
            askPrice0: 0,
            bidPrice0: bidPrice0,
            askGap: 0,
            bidGap: gap,
            fee: 500,
            compound: false
        });

        vm.startPrank(maker);
        exchange.placeETHGridOrders{value: ethAmt}(Currency.wrap(address(sea)), Currency.wrap(address(0)), param);
        vm.stopPrank();

        assertEq(Currency.wrap(address(0)).balanceOf(maker), 0);
        assertEq(Currency.wrap(address(0)).balanceOf(address(exchange)), 0);
        assertEq(weth.balanceOf(maker), 0);
        assertEq(weth.balanceOf(address(exchange)), ethAmt);
        // assertEq(ethAmt > Currency.wrap(address(0)).balanceOf(address(exchange)), true);
        assertEq(
            ethAmt, weth.balanceOf(address(exchange)) + weth.balanceOf(maker)
        );
    }

    function test_PlaceGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address maker = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 askPrice0 = uint160((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        usdc.transfer(maker, usdcAmt);
        sea.transfer(maker, uint256(asks) * perBaseAmt);

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

        vm.startPrank(maker);
        sea.approve(address(exchange), type(uint128).max);
        usdc.approve(address(exchange), type(uint128).max);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(maker));
        assertEq(usdc.balanceOf(maker) > 0, true);
        assertEq(uint256(asks) * perBaseAmt, sea.balanceOf(address(exchange)));
        assertEq(usdcAmt > usdc.balanceOf(address(exchange)), true);
        assertEq(usdcAmt, usdc.balanceOf(address(exchange)) + usdc.balanceOf(maker));
    }

    function test_PlaceETHGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address maker = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 askPrice0 = uint160((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        // eth/usdc
        usdc.transfer(maker, usdcAmt);
        vm.deal(maker, uint256(asks) * perBaseAmt);

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

        vm.startPrank(maker);
        usdc.approve(address(exchange), type(uint128).max);
        exchange.placeETHGridOrders{value: uint256(asks) * perBaseAmt}(
            Currency.wrap(address(0)), Currency.wrap(address(usdc)), param
        );
        vm.stopPrank();

        assertEq(0, Currency.wrap(address(0)).balanceOf(maker));
        assertEq(usdc.balanceOf(maker) > 0, true);
        assertEq(0, Currency.wrap(address(0)).balanceOf(address(exchange)));
        assertEq(uint256(asks) * perBaseAmt, weth.balanceOf(address(exchange)));
        assertEq(usdcAmt > usdc.balanceOf(address(exchange)), true);
        assertEq(usdcAmt, usdc.balanceOf(address(exchange)) + usdc.balanceOf(maker));
    }

    // weth/usdc
    function test_PlaceWETHGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address maker = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 askPrice0 = uint160((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        // eth/usdc
        usdc.transfer(maker, usdcAmt);
        vm.deal(maker, uint256(asks) * perBaseAmt);

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

        vm.startPrank(maker);
        weth.deposit{value: uint256(asks) * perBaseAmt}();
        usdc.approve(address(exchange), type(uint128).max);
        weth.approve(address(exchange), type(uint128).max);
        exchange.placeGridOrders(Currency.wrap(address(weth)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        assertEq(0, Currency.wrap(address(weth)).balanceOf(maker));
        assertEq(usdc.balanceOf(maker) > 0, true);
        assertEq(uint256(asks) * perBaseAmt, Currency.wrap(address(weth)).balanceOf(address(exchange)));
        assertEq(usdcAmt > usdc.balanceOf(address(exchange)), true);
        assertEq(usdcAmt, usdc.balanceOf(address(exchange)) + usdc.balanceOf(maker));
    }

    // sea/weth
    function test_PlaceWETHQuoteGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address maker = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 baseAmt = perBaseAmt * asks;
        uint256 ethAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 askPrice0 = uint160((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        // sea/weth
        sea.transfer(maker, baseAmt);
        vm.deal(maker, ethAmt);

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

        vm.startPrank(maker);
        weth.deposit{value: ethAmt}();
        sea.approve(address(exchange), type(uint128).max);
        weth.approve(address(exchange), type(uint128).max);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(weth)), param);
        vm.stopPrank();

        assertEq(0, Currency.wrap(address(sea)).balanceOf(maker));
        assertEq(weth.balanceOf(maker) > 0, true);
        assertEq(baseAmt, Currency.wrap(address(sea)).balanceOf(address(exchange)));
        assertEq(ethAmt > weth.balanceOf(address(exchange)), true);
        assertEq(ethAmt, weth.balanceOf(maker) + weth.balanceOf(address(exchange)));
    }
}
