// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {GridExBaseTest} from "./GridExBase.t.sol";
import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {IOrderErrors} from "../src/interfaces/IOrderErrors.sol";
import {Currency} from "../src/libraries/Currency.sol";

/// @title GridExFeeTest
/// @notice Tests for fee boundary conditions (MIN_FEE, MAX_FEE)
contract GridExFeeTest is GridExBaseTest {
    // Fee constants from GridOrder.sol
    uint32 public constant MIN_FEE = 100;      // 0.01%
    uint32 public constant MAX_FEE = 100000;   // 10%

    // ============ Fee Boundary Tests ============

    /// @notice Test placing orders with minimum fee
    function test_placeOrders_minFee() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12); // 0.002
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        // Should succeed with MIN_FEE
        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, MIN_FEE);
        
        // Verify grid was created
        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        assertEq(config.fee, MIN_FEE);
    }

    /// @notice Test placing orders with maximum fee
    function test_placeOrders_maxFee() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        // Should succeed with MAX_FEE
        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, MAX_FEE);
        
        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        assertEq(config.fee, MAX_FEE);
    }

    /// @notice Test placing orders with fee below minimum reverts
    function test_placeOrders_revertFeeBelowMin() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, int256(gap)),
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: amt,
            fee: MIN_FEE - 1, // Below minimum
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.InvalidGridFee.selector);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    /// @notice Test placing orders with fee above maximum reverts
    function test_placeOrders_revertFeeAboveMax() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, int256(gap)),
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: amt,
            fee: MAX_FEE + 1, // Above maximum
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.InvalidGridFee.selector);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    /// @notice Test placing orders with zero fee reverts
    function test_placeOrders_revertZeroFee() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, int256(gap)),
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: amt,
            fee: 0, // Zero fee
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.InvalidGridFee.selector);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    /// @notice Test fee at exact boundary (MIN_FEE - 1)
    function test_placeOrders_revertFeeJustBelowMin() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, int256(gap)),
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: amt,
            fee: 99, // Just below MIN_FEE (100)
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.InvalidGridFee.selector);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    /// @notice Test fee at exact boundary (MAX_FEE + 1)
    function test_placeOrders_revertFeeJustAboveMax() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, int256(gap)),
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: amt,
            fee: 100001, // Just above MAX_FEE (100000)
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.InvalidGridFee.selector);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    // ============ Fee Calculation Tests ============

    /// @notice Test fee calculation with minimum fee
    function test_fillOrder_minFeeCalculation() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, MIN_FEE);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        
        uint256 takerUsdcBefore = usdc.balanceOf(taker);
        uint256 takerSeaBefore = sea.balanceOf(taker);
        
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();
        
        uint256 takerUsdcAfter = usdc.balanceOf(taker);
        uint256 takerSeaAfter = sea.balanceOf(taker);
        
        // Taker should receive base tokens
        assertEq(takerSeaAfter - takerSeaBefore, amt);
        // Taker should pay quote tokens (including fee)
        assertTrue(takerUsdcBefore > takerUsdcAfter);
    }

    /// @notice Test fee calculation with maximum fee
    function test_fillOrder_maxFeeCalculation() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, MAX_FEE);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        
        uint256 takerUsdcBefore = usdc.balanceOf(taker);
        uint256 takerSeaBefore = sea.balanceOf(taker);
        
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();
        
        uint256 takerUsdcAfter = usdc.balanceOf(taker);
        uint256 takerSeaAfter = sea.balanceOf(taker);
        
        // Taker should receive base tokens
        assertEq(takerSeaAfter - takerSeaBefore, amt);
        // Taker should pay quote tokens (including higher fee)
        assertTrue(takerUsdcBefore > takerUsdcAfter);
    }

    /// @notice Fuzz test for valid fee range
    function testFuzz_placeOrders_validFeeRange(uint32 fee) public {
        fee = uint32(bound(fee, MIN_FEE, MAX_FEE));
        
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, int256(gap)),
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: amt,
            fee: fee,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
        
        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        assertEq(config.fee, fee);
    }

    /// @notice Fuzz test for invalid fee range (below min)
    function testFuzz_placeOrders_invalidFeeBelowMin(uint32 fee) public {
        vm.assume(fee < MIN_FEE);
        
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, int256(gap)),
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: amt,
            fee: fee,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.InvalidGridFee.selector);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    /// @notice Fuzz test for invalid fee range (above max)
    function testFuzz_placeOrders_invalidFeeAboveMax(uint32 fee) public {
        vm.assume(fee > MAX_FEE);
        
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            askData: abi.encode(askPrice0, int256(gap)),
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: amt,
            fee: fee,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.InvalidGridFee.selector);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    // ============ ETH Grid Fee Tests ============

    /// @notice Test ETH grid orders with minimum fee
    function test_placeETHGridOrders_minFee() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 0.01 ether;

        _placeOrders(address(0), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, MIN_FEE);
        
        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        assertEq(config.fee, MIN_FEE);
    }

    /// @notice Test ETH grid orders with maximum fee
    function test_placeETHGridOrders_maxFee() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 0.01 ether;

        _placeOrders(address(0), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, MAX_FEE);
        
        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        assertEq(config.fee, MAX_FEE);
    }

    // ============ Protocol Fee Distribution Tests ============

    /// @notice Test that protocol fees are sent to vault
    function test_protocolFee_sentToVault() public {
        // Use price that results in meaningful fees with USDC (6 decimals)
        uint256 askPrice0 = PRICE_MULTIPLIER / 100 / (10 ** 12); // 0.01 USDC per token
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 10000 ether; // 10000 tokens
        uint128 orderId = 0x80000000000000000000000000000001;

        // Give maker more tokens
        sea.transfer(maker, 100000 ether);
        usdc.transfer(maker, 10000_000_000); // 10000 USDC
        
        vm.startPrank(maker);
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        vm.stopPrank();

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 10000); // 1% fee

        uint256 gridOrderId = toGridOrderId(1, orderId);
        
        uint256 vaultUsdcBefore = usdc.balanceOf(vault);
        
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();
        
        uint256 vaultUsdcAfter = usdc.balanceOf(vault);
        
        // Vault should receive protocol fee
        assertTrue(vaultUsdcAfter > vaultUsdcBefore, "Vault should receive protocol fee");
    }

    /// @notice Test LP fee accumulation in grid profits
    function test_lpFee_accumulatedInProfits() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        
        // Fill ask order
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();
        
        // Fill the reverse bid order (ERC20 pair, flag=0 for no ETH)
        vm.startPrank(taker);
        exchange.fillBidOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();
        
        // Check grid profits
        uint256 profits = exchange.getGridProfits(1);
        assertTrue(profits > 0, "Grid should have accumulated profits");
    }
}
