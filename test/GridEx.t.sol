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
import {GridOrder} from "../src/GridOrder.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

contract GridExTest is Test, IGridExCallback {
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
        sea.transfer(address(this), baseAmt);

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
        address other = address(0x123);
        exchange.placeGridOrders(other, address(sea), address(usdc), param);
    }

    function test_PlaceBidGridOrder() public {
        uint16 bids = 10;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        usdc.transfer(address(this), usdcAmt);

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
        address other = address(0x123);
        exchange.placeGridOrders(other, address(sea), address(usdc), param);
    }

    function test_PlaceGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address other = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        sea.transfer(address(this), uint256(asks) * perBaseAmt);
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint160 askPrice0 = uint160((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 bidPrice0 = uint160((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint160 gap = uint160((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        usdc.transfer(address(this), usdcAmt);

        // vm.startPrank(other);
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
        // sea.approve(address(exchange), type(uint96).max);
        // usdc.approve(address(exchange), type(uint96).max);
        vm.expectEmit(true, true, true, true);
        emit IPair.PairCreated(address(sea), address(usdc), 1);

        exchange.placeGridOrders(other, address(sea), address(usdc), param);
        // vm.stopPrank();

        // assertEq(0, sea.balanceOf(other));
        // uint256 usdcUsed = 0;
        // uint160 buyPrice = bidPrice0;
        // for (uint i = 0; i < bids; i++) {
        //     usdcUsed += exchange.calcQuoteAmount((perBaseAmt), (buyPrice), false);
        //     buyPrice -= gap;
        // }
        // console.log(usdcAmt - usdcUsed);
        // assertEq(usdc.balanceOf(other), usdcAmt - usdcUsed);
    }

    function gridExPlaceOrderCallback(address token, uint256 amount) public {
        console.log(token);
        console.log(amount);
        transferToken(token, amount);
    }

    function gridExSwapCallback(address token, uint256 amount) public {
        transferToken(token, amount);
    }

    function transferToken(address token, uint256 amount) private {
        if (token == address(weth)) {
            WETH(weth).deposit{value: amount}();
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            SafeTransferLib.safeTransfer(ERC20(token), msg.sender, amount);
        }
    }
}
