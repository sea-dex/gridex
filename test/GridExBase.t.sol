// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// import {IWETH} from "../src/interfaces/IWETH.sol";
// import {IPair} from "../src/interfaces/IPair.sol";
import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
// import {IGridEx} from "../src/interfaces/IGridEx.sol";
// import {IGridExCallback} from "../src/interfaces/IGridExCallback.sol";
// import {IOrderEvents} from "../src/interfaces/IOrderEvents.sol";

import {Test} from "forge-std/Test.sol";
// import {ERC20} from "solmate/tokens/ERC20.sol";

import {GridEx} from "../src/GridEx.sol";
// import {GridOrder} from "../src/GridOrder.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {Lens} from "../src/libraries/Lens.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

contract GridExBaseTest is Test {
    WETH public weth;
    GridEx public exchange;
    Linear public linear;
    SEA public sea;
    USDC public usdc;
    address public vault = address(0x0888880);

    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;
    address maker = address(0x100);
    address taker = address(0x200);
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256 initialETHAmt = 10 ether;
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256 initialSEAAmt = 1000000 ether;
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256 initialUSDCAmt = 10000_000_000; 

    function setUp() public {
        weth = new WETH();
        sea = new SEA();
        usdc = new USDC();
        exchange = new GridEx(address(weth), address(usdc), vault);
        linear = new Linear(address(exchange));

        vm.deal(maker, initialETHAmt);
        // forge-lint: disable-next-line
        sea.transfer(maker, initialSEAAmt);
        // forge-lint: disable-next-line
        usdc.transfer(maker, initialUSDCAmt);

        vm.deal(taker, initialETHAmt);
        // forge-lint: disable-next-line
        sea.transfer(taker, initialSEAAmt);
        // forge-lint: disable-next-line
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

    function toGridOrderId(uint128 gridId, uint128 orderId) internal pure returns (uint256) {
        return uint256(uint256(gridId) << 128) | uint256(orderId);
    }

    function _placeOrdersBy(
        address who,
        address base,
        address quote,
        uint128 perBaseAmt,
        uint16 asks,
        uint16 bids,
        uint256 askPrice0,
        uint256 bidPrice0,
        uint256 gap,
        bool compound,
        uint32 fee
    ) internal {
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
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
            uint256 val = (base == address(0)) ? perBaseAmt * asks : (perBaseAmt * bids * bidPrice0) / PRICE_MULTIPLIER;

            exchange.placeETHGridOrders{value: val}(Currency.wrap(base), Currency.wrap(quote), param);
        } else {
            exchange.placeGridOrders(Currency.wrap(base), Currency.wrap(quote), param);
        }
        vm.stopPrank();
    }

    function _placeOrders(
        address base,
        address quote,
        uint128 perBaseAmt,
        uint16 asks,
        uint16 bids,
        uint256 askPrice0,
        uint256 bidPrice0,
        uint256 gap,
        bool compound,
        uint32 fee
    ) internal {
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
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
            uint256 val = (base == address(0)) ? perBaseAmt * asks : (perBaseAmt * bids * bidPrice0) / PRICE_MULTIPLIER;

            exchange.placeETHGridOrders{value: val}(Currency.wrap(base), Currency.wrap(quote), param);
        } else {
            exchange.placeGridOrders(Currency.wrap(base), Currency.wrap(quote), param);
        }
        vm.stopPrank();
    }

    function _placeOneshotOrders(
        address base,
        address quote,
        uint128 perBaseAmt,
        uint16 asks,
        uint16 bids,
        uint256 askPrice0,
        uint256 bidPrice0,
        uint256 gap,
        bool compound,
        uint32 fee
    ) internal {
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
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
            uint256 val = (base == address(0)) ? perBaseAmt * asks : (perBaseAmt * bids * bidPrice0) / PRICE_MULTIPLIER;

            exchange.placeETHGridOrders{value: val}(Currency.wrap(base), Currency.wrap(quote), param);
        } else {
            exchange.placeGridOrders(Currency.wrap(base), Currency.wrap(quote), param);
        }
        vm.stopPrank();
    }

    // just for ask order
    // return: fillVol, reverse order quote amount, grid profit, fee
    function calcQuoteVolReversed(
        uint256 price,
        uint256 gap,
        uint128 fillAmt,
        uint128 baseAmt,
        uint128 currOrderQuoteAmt,
        uint32 feebps
    ) internal pure returns (uint128, uint128, uint128, uint128) {
        (uint128 quoteVol, uint128 fee) = Lens.calcAskOrderQuoteAmount(price, fillAmt, feebps);
        uint128 lpfee = calcMakerFee(fee);
        uint128 quota = Lens.calcQuoteAmount(baseAmt, price - gap, false);
        if (currOrderQuoteAmt >= quota) {
            return (quoteVol, quota, quota + lpfee, fee);
        }
        if (currOrderQuoteAmt + quoteVol + lpfee > quota) {
            return (quoteVol, quota, currOrderQuoteAmt + quoteVol + lpfee - quota, fee);
        }
        return (quoteVol, quoteVol + lpfee, 0, fee);
    }

    // just for ask order
    // return: fillVol, reverse order quote amount, fee
    function calcQuoteVolReversedCompound(uint256 price, uint128 fillAmt, uint32 feebps)
        internal
        pure
        returns (uint128, uint128, uint128)
    {
        (uint128 quoteVol, uint128 fee) = Lens.calcAskOrderQuoteAmount(price, fillAmt, feebps);
        uint128 lpfee = calcMakerFee(fee);
        return (quoteVol, quoteVol + lpfee, fee);
    }

    function calcProtocolFee(uint128 fee) internal pure returns (uint128) {
        return (fee * 60) / 100;
    }

    function calcMakerFee(uint128 fee) internal pure returns (uint128) {
        return fee - ((fee * 60) / 100);
        // return fee - (fee >> 1);
    }
}
