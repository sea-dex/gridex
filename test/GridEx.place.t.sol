// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {IWETH} from "../src/interfaces/IWETH.sol";
import {IPair} from "../src/interfaces/IPair.sol";
import {IGridEx} from "../src/interfaces/IGridEx.sol";
// import {IGridExCallback} from "../src/interfaces/IGridExCallback.sol";
import {IOrderEvents} from "../src/interfaces/IOrderEvents.sol";

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {GridEx} from "../src/GridEx.sol";
import {GridOrder} from "../src/GridOrder.sol";
import {Currency, CurrencyLibrary} from "../src/libraries/Currency.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

contract GridExTest is Test {
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

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    function test_PlaceAskGridOrder() public {
        uint16 asks = 13;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 baseAmt = uint256(asks) * perBaseAmt;
        uint160 askPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        address other = address(0x123);

        sea.transfer(other, baseAmt);

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

        vm.startPrank(other);
        sea.approve(address(exchange), type(uint96).max);
        exchange.placeGridOrders(
            Currency.wrap(address(sea)),
            Currency.wrap(address(usdc)),
            param
        );
        vm.stopPrank();

        assertEq(sea.balanceOf(other), 0);
        assertEq(uint256(asks) * perBaseAmt, sea.balanceOf(address(exchange)));
    }

    function test_PlaceETHBaseAskGridOrder() public {
        uint16 asks = 13;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 baseAmt = uint256(asks) * perBaseAmt;
        uint160 askPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        address other = address(0x123);

        vm.deal(other, baseAmt);

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

        vm.startPrank(other);
        exchange.placeGridOrders{value: baseAmt}(
            Currency.wrap(address(0)),
            Currency.wrap(address(usdc)),
            param
        );
        vm.stopPrank();

        assertEq(Currency.wrap(address(0)).balanceOf(other), 0);
        assertEq(uint256(asks) * perBaseAmt, Currency.wrap(address(0)).balanceOf(address(exchange)));
    }

    function test_PlaceBidGridOrder() public {
        uint16 bids = 10;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        address other = address(0x123);

        usdc.transfer(other, usdcAmt);

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

        vm.startPrank(other);
        usdc.approve(address(exchange), type(uint96).max);
        exchange.placeGridOrders(
            Currency.wrap(address(sea)),
            Currency.wrap(address(usdc)),
            param
        );
        vm.stopPrank();

        assertEq(usdc.balanceOf(other) > 0, true);
        assertEq(usdcAmt > usdc.balanceOf(address(exchange)), true);
        assertEq(usdcAmt, usdc.balanceOf(other) + usdc.balanceOf(address(exchange)));
    }

    function test_PlaceETHQuoteBidGridOrder() public {
        uint16 bids = 10;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 ethAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        address other = address(0x123);

        vm.deal(other, ethAmt);

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

        vm.startPrank(other);
        exchange.placeGridOrders{value: ethAmt}(
            Currency.wrap(address(sea)),
            Currency.wrap(address(0)),
            param
        );
        vm.stopPrank();

        assertEq(Currency.wrap(address(0)).balanceOf(other) > 0, true);
        assertEq(ethAmt > Currency.wrap(address(0)).balanceOf(address(exchange)), true);
        assertEq(ethAmt, Currency.wrap(address(0)).balanceOf(address(exchange)) + Currency.wrap(address(0)).balanceOf(other));
    }

    function test_PlaceGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address other = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 askPrice0 = uint160((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        usdc.transfer(other, usdcAmt);
        sea.transfer(other, uint256(asks) * perBaseAmt);

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

        vm.startPrank(other);
        sea.approve(address(exchange), type(uint96).max);
        usdc.approve(address(exchange), type(uint96).max);
        exchange.placeGridOrders(
            Currency.wrap(address(sea)),
            Currency.wrap(address(usdc)),
            param
        );
        vm.stopPrank();

        assertEq(0, sea.balanceOf(other));
        assertEq(usdc.balanceOf(other) > 0, true);
        assertEq(uint256(asks) * perBaseAmt, sea.balanceOf(address(exchange)));
        assertEq(usdcAmt > usdc.balanceOf(address(exchange)), true);
        assertEq(usdcAmt, usdc.balanceOf(address(exchange)) + usdc.balanceOf(other));
    }

    function test_PlaceETHGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address other = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 askPrice0 = uint160((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        // eth/usdc
        usdc.transfer(other, usdcAmt);
        vm.deal(other, uint256(asks) * perBaseAmt);

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

        vm.startPrank(other);
        usdc.approve(address(exchange), type(uint96).max);
        exchange.placeGridOrders{value: uint256(asks) * perBaseAmt}(
            Currency.wrap(address(0)),
            Currency.wrap(address(usdc)),
            param
        );
        vm.stopPrank();

        assertEq(0, Currency.wrap(address(0)).balanceOf(other));
        assertEq(usdc.balanceOf(other) > 0, true);
        assertEq(uint256(asks) * perBaseAmt, Currency.wrap(address(0)).balanceOf(address(exchange)));
        assertEq(usdcAmt > usdc.balanceOf(address(exchange)), true);
        assertEq(usdcAmt, usdc.balanceOf(address(exchange)) + usdc.balanceOf(other));
    }

    // weth/usdc
    function test_PlaceWETHGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address other = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 askPrice0 = uint160((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        // eth/usdc
        usdc.transfer(other, usdcAmt);
        vm.deal(other, uint256(asks) * perBaseAmt);

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

        vm.startPrank(other);
        weth.deposit{value: uint256(asks) * perBaseAmt}();
        usdc.approve(address(exchange), type(uint96).max);
        weth.approve(address(exchange), type(uint96).max);
        exchange.placeGridOrders(
            Currency.wrap(address(weth)),
            Currency.wrap(address(usdc)),
            param
        );
        vm.stopPrank();

        assertEq(0, Currency.wrap(address(weth)).balanceOf(other));
        assertEq(usdc.balanceOf(other) > 0, true);
        assertEq(uint256(asks) * perBaseAmt, Currency.wrap(address(weth)).balanceOf(address(exchange)));
        assertEq(usdcAmt > usdc.balanceOf(address(exchange)), true);
        assertEq(usdcAmt, usdc.balanceOf(address(exchange)) + usdc.balanceOf(other));
    }

    // sea/weth
    function test_PlaceWETHQuoteGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address other = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 baseAmt = perBaseAmt * asks;
        uint256 ethAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 askPrice0 = uint160((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        // sea/weth
        sea.transfer(other, baseAmt);
        vm.deal(other, ethAmt);

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

        vm.startPrank(other);
        weth.deposit{value: ethAmt}();
        sea.approve(address(exchange), type(uint96).max);
        weth.approve(address(exchange), type(uint96).max);
        exchange.placeGridOrders(
            Currency.wrap(address(sea)),
            Currency.wrap(address(weth)),
            param
        );
        vm.stopPrank();

        assertEq(0, Currency.wrap(address(sea)).balanceOf(other));
        assertEq(weth.balanceOf(other) > 0, true);
        assertEq(baseAmt, Currency.wrap(address(sea)).balanceOf(address(exchange)));
        assertEq(ethAmt > weth.balanceOf(address(exchange)), true);
        assertEq(ethAmt, weth.balanceOf(other) + weth.balanceOf(address(exchange)));
    }
}
