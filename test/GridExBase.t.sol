// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IWETH} from "../src/interfaces/IWETH.sol";
import {IPair} from "../src/interfaces/IPair.sol";
import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {IGridEx} from "../src/interfaces/IGridEx.sol";
// import {IGridExCallback} from "../src/interfaces/IGridExCallback.sol";
import {IOrderEvents} from "../src/interfaces/IOrderEvents.sol";

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {GridEx} from "../src/GridEx.sol";
import {GridOrder} from "../src/GridOrder.sol";
import {Currency, CurrencyLibrary} from "../src/libraries/Currency.sol";
import {Linear} from "../src/strategy/Linear.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

contract GridExBaseTest is Test {
    WETH public weth;
    GridEx public exchange;
    Linear public linear;
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
        linear = new Linear();

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

    function toGridOrderId(
        uint128 gridId,
        uint128 orderId
    ) internal pure returns (uint256) {
        return uint256(uint256(gridId) << 128) | uint256(orderId);
    }

    function _placeOrdersBy(
        address who,
        address base,
        address quote,
        uint128 perBaseAmt,
        uint16 asks,
        uint16 bids,
        uint160 askPrice0,
        uint160 bidPrice0,
        uint160 gap,
        bool compound,
        uint32 fee
    ) internal {
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, int160(gap)),
            bidData: abi.encode(bidPrice0, -int160(gap)),
            askOrderCount: asks,
            bidOrderCount: bids,
            baseAmount: perBaseAmt,
            // askPrice0: askPrice0,
            // bidPrice0: bidPrice0,
            // askGap: gap,
            // bidGap: gap,
            fee: fee,
            compound: compound,
            oneshot: false
        });

        vm.startPrank(who);
        if (base == address(0) || quote == address(0)) {
            uint256 val = (base == address(0))
                ? perBaseAmt * asks
                : (perBaseAmt * bids * bidPrice0) / PRICE_MULTIPLIER;

            exchange.placeETHGridOrders{value: val}(
                Currency.wrap(base),
                Currency.wrap(quote),
                param
            );
        } else {
            exchange.placeGridOrders(
                Currency.wrap(base),
                Currency.wrap(quote),
                param
            );
        }
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
        uint160 gap,
        bool compound,
        uint32 fee
    ) internal {
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, int160(gap)),
            bidData: abi.encode(bidPrice0, -int160(gap)),
            askOrderCount: asks,
            bidOrderCount: bids,
            baseAmount: perBaseAmt,
            // askPrice0: askPrice0,
            // bidPrice0: bidPrice0,
            // askGap: gap,
            // bidGap: gap,
            fee: fee,
            compound: compound,
            oneshot: false
        });

        vm.startPrank(maker);
        if (base == address(0) || quote == address(0)) {
            uint256 val = (base == address(0))
                ? perBaseAmt * asks
                : (perBaseAmt * bids * bidPrice0) / PRICE_MULTIPLIER;

            exchange.placeETHGridOrders{value: val}(
                Currency.wrap(base),
                Currency.wrap(quote),
                param
            );
        } else {
            exchange.placeGridOrders(
                Currency.wrap(base),
                Currency.wrap(quote),
                param
            );
        }
        vm.stopPrank();
    }

    function _placeOneshotOrders(
        address base,
        address quote,
        uint128 perBaseAmt,
        uint16 asks,
        uint16 bids,
        uint160 askPrice0,
        uint160 bidPrice0,
        uint160 gap,
        bool compound,
        uint32 fee
    ) internal {
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, int160(gap)),
            bidData: abi.encode(bidPrice0, -int160(gap)),
            askOrderCount: asks,
            bidOrderCount: bids,
            baseAmount: perBaseAmt,
            // askPrice0: askPrice0,
            // bidPrice0: bidPrice0,
            // askGap: gap,
            // bidGap: gap,
            fee: fee,
            compound: compound,
            oneshot: true
        });

        vm.startPrank(maker);
        if (base == address(0) || quote == address(0)) {
            uint256 val = (base == address(0))
                ? perBaseAmt * asks
                : (perBaseAmt * bids * bidPrice0) / PRICE_MULTIPLIER;

            exchange.placeETHGridOrders{value: val}(
                Currency.wrap(base),
                Currency.wrap(quote),
                param
            );
        } else {
            exchange.placeGridOrders(
                Currency.wrap(base),
                Currency.wrap(quote),
                param
            );
        }
        vm.stopPrank();
    }

    // just for ask order
    // return: fillVol, reverse order quote amount, grid profit, fee
    function calcQuoteVolReversed(
        uint160 price,
        uint160 gap,
        uint128 fillAmt,
        uint128 baseAmt,
        uint128 currOrderQuoteAmt,
        uint32 feebps
    ) internal view returns (uint128, uint128, uint128, uint128) {
        (uint128 quoteVol, uint128 fee) = exchange.calcAskOrderQuoteAmount(
            price,
            fillAmt,
            feebps
        );
        uint128 lpfee = fee - (fee >> 1);
        uint128 quota = exchange.calcQuoteAmount(baseAmt, price - gap, false);
        if (currOrderQuoteAmt >= quota) {
            return (quoteVol, quota, quota + lpfee, fee);
        }
        if (currOrderQuoteAmt + quoteVol + lpfee > quota) {
            return (
                quoteVol,
                quota,
                currOrderQuoteAmt + quoteVol + lpfee - quota,
                fee
            );
        }
        return (quoteVol, quoteVol + lpfee, 0, fee);
    }

    // just for ask order
    // return: fillVol, reverse order quote amount, fee
    function calcQuoteVolReversedCompound(
        uint160 price,
        uint128 fillAmt,
        uint32 feebps
    ) internal view returns (uint128, uint128, uint128) {
        (uint128 quoteVol, uint128 fee) = exchange.calcAskOrderQuoteAmount(
            price,
            fillAmt,
            feebps
        );
        uint128 lpfee = fee - (fee >> 1);
        return (quoteVol, quoteVol + lpfee, fee);
    }

    function makerFee(uint128 fee) internal pure returns (uint128) {
        return fee - (fee >> 1);
    }
}
