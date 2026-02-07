// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";

import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {IOrderErrors} from "../src/interfaces/IOrderErrors.sol";
import {IOrderEvents} from "../src/interfaces/IOrderEvents.sol";
import {GridEx} from "../src/GridEx.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {Currency} from "../src/libraries/Currency.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

contract GridExStrategyWhitelistTest is Test {
    WETH public weth;
    GridEx public exchange;
    Linear public linear;
    Linear public linear2;
    SEA public sea;
    USDC public usdc;
    address public vault = address(0x0888880);

    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;
    address maker = address(0x100);
    address nonOwner = address(0x200);

    function setUp() public {
        weth = new WETH();
        sea = new SEA();
        usdc = new USDC();
        exchange = new GridEx(address(weth), address(usdc), vault);
        linear = new Linear(address(exchange));
        linear2 = new Linear(address(exchange));

        // Set oneshot protocol fee
        exchange.setOneshotProtocolFeeBps(500);

        // Give maker some tokens
        // forge-lint: disable-next-line
        sea.transfer(maker, 1000000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(maker, 10000_000_000);

        vm.startPrank(maker);
        sea.approve(address(exchange), type(uint128).max);
        usdc.approve(address(exchange), type(uint128).max);
        vm.stopPrank();
    }

    function test_setStrategyWhitelist_onlyOwner() public {
        // Non-owner should not be able to whitelist
        vm.startPrank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        exchange.setStrategyWhitelist(address(linear), true);
        vm.stopPrank();

        // Owner should be able to whitelist
        exchange.setStrategyWhitelist(address(linear), true);
        assertTrue(exchange.isStrategyWhitelisted(address(linear)));
    }

    function test_setStrategyWhitelist_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IOrderEvents.StrategyWhitelistUpdated(address(this), address(linear), true);
        exchange.setStrategyWhitelist(address(linear), true);
    }

    function test_setStrategyWhitelist_canRemove() public {
        // Whitelist first
        exchange.setStrategyWhitelist(address(linear), true);
        assertTrue(exchange.isStrategyWhitelisted(address(linear)));

        // Remove from whitelist
        exchange.setStrategyWhitelist(address(linear), false);
        assertFalse(exchange.isStrategyWhitelisted(address(linear)));
    }

    function test_setStrategyWhitelist_revertZeroAddress() public {
        vm.expectRevert("Invalid strategy address");
        exchange.setStrategyWhitelist(address(0), true);
    }

    function test_placeGridOrders_revertNonWhitelistedAskStrategy() public {
        // Don't whitelist the strategy
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 askPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: 5,
            bidOrderCount: 0,
            baseAmount: perBaseAmt,
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(0, -int256(gap)),
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.StrategyNotWhitelisted.selector);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    function test_placeGridOrders_revertNonWhitelistedBidStrategy() public {
        // Whitelist only linear, not linear2
        exchange.setStrategyWhitelist(address(linear), true);

        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 bidPrice0 = uint256((48 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: 0,
            bidOrderCount: 5,
            baseAmount: perBaseAmt,
            askStrategy: linear,
            bidStrategy: linear2, // Not whitelisted
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.StrategyNotWhitelisted.selector);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    function test_placeGridOrders_successWithWhitelistedStrategy() public {
        // Whitelist the strategy
        exchange.setStrategyWhitelist(address(linear), true);

        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 askPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 bidPrice0 = uint256((48 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: perBaseAmt,
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        // Verify grid was created
        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        assertEq(config.owner, maker);
        assertEq(config.askOrderCount, 5);
        assertEq(config.bidOrderCount, 5);
    }

    function test_placeETHGridOrders_revertNonWhitelistedStrategy() public {
        // Don't whitelist the strategy
        uint128 perBaseAmt = 1 ether;
        uint256 askPrice0 = uint256((2000 * PRICE_MULTIPLIER) / (10 ** 12));
        uint256 gap = uint256((10 * PRICE_MULTIPLIER) / (10 ** 12));

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: 5,
            bidOrderCount: 0,
            baseAmount: perBaseAmt,
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(0, -int256(gap)),
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.deal(maker, 10 ether);
        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.StrategyNotWhitelisted.selector);
        exchange.placeETHGridOrders{value: 5 ether}(Currency.wrap(address(0)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    function test_multipleStrategiesCanBeWhitelisted() public {
        // Whitelist both strategies
        exchange.setStrategyWhitelist(address(linear), true);
        exchange.setStrategyWhitelist(address(linear2), true);

        assertTrue(exchange.isStrategyWhitelisted(address(linear)));
        assertTrue(exchange.isStrategyWhitelisted(address(linear2)));

        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 askPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 bidPrice0 = uint256((48 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        // Use different strategies for ask and bid
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: perBaseAmt,
            askStrategy: linear,
            bidStrategy: linear2,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        // Verify grid was created with different strategies
        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        assertEq(address(config.askStrategy), address(linear));
        assertEq(address(config.bidStrategy), address(linear2));
    }
}
