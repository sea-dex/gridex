// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

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

contract GridExFillTest is Test {
    WETH public weth;
    GridEx public exchange;
    SEA public sea;
    USDC public usdc;

    uint256 public constant PRICE_MULTIPLIER = 10 ** 29;
    address maker = address(0x100);
    address taker = address(0x200);
    uint256 initialETHAmt = 10 ether;
    uint256 initialSEAAmt = 1000000 ether;
    uint256 initialUSDCAmt = 10000_000_000;

    function setUp() public {
        weth = new WETH();
        sea = new SEA();
        usdc = new USDC();
        exchange = new GridEx(address(weth), address(usdc));

        vm.deal(maker, initialETHAmt);
        sea.transfer(maker, initialSEAAmt);
        usdc.transfer(maker, initialUSDCAmt);

        vm.deal(taker, initialETHAmt);
        sea.transfer(taker, initialSEAAmt);
        usdc.transfer(taker, initialUSDCAmt);

        vm.startPrank(maker);
        weth.approve(address(exchange), type(uint128).max);
        sea.approve(address(exchange), type(uint128).max);
        usdc.approve(address(exchange), type(uint128).max);
        vm.stopPrank();

        vm.startPrank(taker);
        weth.approve(address(exchange), type(uint128).max);
        sea.approve(address(exchange), type(uint128).max);
        usdc.approve(address(exchange), type(uint128).max);
        vm.stopPrank();
    }

    function _placeOrders(
        address base,
        address quote,
        uint128 perBaseAmt,
        uint16 asks,
        uint16 bids,
        uint160 askPrice0,
        uint160 bidPrice0,
        uint160 gap
    ) private {
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
        if (base == address(0) || quote == address(0)) {
            uint256 val = (base == address(0)) ? perBaseAmt * asks : perBaseAmt * bids * bidPrice0 / PRICE_MULTIPLIER;

            exchange.placeGridOrders{value: val}(Currency.wrap(base), Currency.wrap(quote), param);
        } else {
            exchange.placeGridOrders(Currency.wrap(base), Currency.wrap(quote), param);
        }
        vm.stopPrank();
    }

    function test_fillAskOrder() public {
        uint160 askPrice0 = uint160(PRICE_MULTIPLIER / 500 / (10 ** 12)); // 0.002
        uint160 gap = askPrice0 / 20; // 0.0001
        _placeOrders(address(sea), address(usdc), 20000 ether, 10, 0, askPrice0, 0, gap);

    }

    function test_partialFillAskOrder() public {}

    function test_partialFillAskOrders() public {}
}
