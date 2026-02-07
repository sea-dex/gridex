// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {GridExBaseTest} from "./GridExBase.t.sol";
import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {IGridStrategy} from "../src/interfaces/IGridStrategy.sol";
import {IOrderErrors} from "../src/interfaces/IOrderErrors.sol";
import {IProtocolErrors} from "../src/interfaces/IProtocolErrors.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {Lens} from "../src/libraries/Lens.sol";
import {IERC20Minimal} from "../src/interfaces/IERC20Minimal.sol";
import {ERC20} from "./utils/ERC20.sol";

/// @title GridExEdgeTest
/// @notice Tests for edge cases: max order counts, minimum amounts, equal priority tokens, failed ETH refunds
contract GridExEdgeTest is GridExBaseTest {
    Currency eth = Currency.wrap(address(0));

    // ============ Maximum Order Count Tests ============

    /// @notice Test placing maximum number of ask orders
    function test_maxAskOrderCount() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 100; // Small gap to allow many orders
        uint128 amt = 0.01 ether; // Small amount per order

        // Place 100 ask orders (large but reasonable)
        uint32 askCount = 100;

        vm.startPrank(maker);
        sea.approve(address(exchange), type(uint256).max);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: abi.encode(askPrice0, gap),
            bidData: "",
            askOrderCount: askCount,
            bidOrderCount: 0,
            fee: 500,
            compound: false,
            oneshot: false,
            baseAmount: amt
        });

        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        // Verify all orders were created
        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        assertEq(config.askOrderCount, askCount);
        assertEq(config.bidOrderCount, 0);
    }

    /// @notice Test placing maximum number of bid orders
    function test_maxBidOrderCount() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        // forge-lint: disable-next-line
        int256 gap = -int256(askPrice0 / 1000); // Negative gap for bid orders
        uint256 bidPrice0 = askPrice0 * 100; // Start high enough to accommodate 100 orders
        uint128 amt = 0.01 ether;

        // Place 100 bid orders
        uint32 bidCount = 100;

        vm.startPrank(maker);
        usdc.approve(address(exchange), type(uint256).max);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: "",
            bidData: abi.encode(bidPrice0, gap),
            askOrderCount: 0,
            bidOrderCount: bidCount,
            fee: 500,
            compound: false,
            oneshot: false,
            baseAmount: amt
        });

        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        // Verify all orders were created
        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        assertEq(config.askOrderCount, 0);
        assertEq(config.bidOrderCount, bidCount);
    }

    /// @notice Test placing both ask and bid orders at maximum
    function test_maxBothOrderCounts() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        // forge-lint: disable-next-line
        uint256 askGap = askPrice0 / 1000; // Positive gap for ask orders
        // forge-lint: disable-next-line
        int256 bidGap = -int256(askPrice0 / 1000); // Negative gap for bid orders
        uint256 bidPrice0 = askPrice0 * 50; // Start high enough for 50 bid orders
        uint128 amt = 0.01 ether;

        uint32 askCount = 50;
        uint32 bidCount = 50;

        vm.startPrank(maker);
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: abi.encode(askPrice0, askGap),
            bidData: abi.encode(bidPrice0, bidGap),
            askOrderCount: askCount,
            bidOrderCount: bidCount,
            fee: 500,
            compound: false,
            oneshot: false,
            baseAmount: amt
        });

        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        assertEq(config.askOrderCount, askCount);
        assertEq(config.bidOrderCount, bidCount);
    }

    // ============ Minimum Amount Tests ============

    /// @notice Test that amounts too small to produce quote volume are rejected
    function test_minimumBaseAmount_tooSmall_reverts() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 askGap = askPrice0 / 20;
        // forge-lint: disable-next-line
        int256 bidGap = -int256(askPrice0 / 20); // Negative gap for bid orders
        uint256 bidPrice0 = askPrice0 * 2; // Higher bid price

        // Very small amount - 1 wei results in zero quote amount
        uint128 amt = 1;

        vm.startPrank(maker);
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: abi.encode(askPrice0, askGap),
            bidData: abi.encode(bidPrice0, bidGap),
            askOrderCount: 1,
            bidOrderCount: 1,
            fee: 500,
            compound: false,
            oneshot: false,
            baseAmount: amt
        });

        // Should revert with ZeroQuoteAmt because 1 wei * price / PRICE_MULTIPLIER = 0
        vm.expectRevert();
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    /// @notice Test placing orders with small but viable amounts
    function test_minimumBaseAmount_viable() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 askGap = askPrice0 / 20;
        // forge-lint: disable-next-line
        int256 bidGap = -int256(askPrice0 / 20); // Negative gap for bid orders
        uint256 bidPrice0 = askPrice0 * 2; // Higher bid price

        // Small but viable amount - enough to produce non-zero quote
        uint128 amt = 1e15; // 0.001 ether

        vm.startPrank(maker);
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: abi.encode(askPrice0, askGap),
            bidData: abi.encode(bidPrice0, bidGap),
            askOrderCount: 1,
            bidOrderCount: 1,
            fee: 500,
            compound: false,
            oneshot: false,
            baseAmount: amt
        });

        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        assertEq(config.baseAmt, amt);
    }

    /// @notice Test filling with minimum amount
    function test_fillMinimumAmount() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Fill with minimum amount (1 wei)
        uint128 fillAmt = 1;

        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify partial fill
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        assertEq(order.amount, amt - fillAmt);
    }

    // ============ Equal Priority Token Tests ============

    /// @notice Test pair creation with equal priority tokens (base < quote by address)
    function test_equalPriorityTokens_baseSmaller() public {
        // Create two tokens with equal priority
        TestToken tokenA = new TestToken("Token A", "TKA", 18);
        TestToken tokenB = new TestToken("Token B", "TKB", 18);

        // Set equal priority
        vm.startPrank(exchange.owner());
        exchange.setQuoteToken(Currency.wrap(address(tokenA)), 100);
        exchange.setQuoteToken(Currency.wrap(address(tokenB)), 100);
        vm.stopPrank();

        // Determine which is smaller by address
        address smaller = address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB);
        address larger = address(tokenA) < address(tokenB) ? address(tokenB) : address(tokenA);

        // Mint tokens to maker
        TestToken(smaller).mint(maker, 1000 ether);
        TestToken(larger).mint(maker, 1000 ether);

        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;

        vm.startPrank(maker);
        IERC20Minimal(smaller).approve(address(exchange), type(uint256).max);
        IERC20Minimal(larger).approve(address(exchange), type(uint256).max);

        // base < quote should work
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: abi.encode(askPrice0, gap),
            bidData: "",
            askOrderCount: 1,
            bidOrderCount: 0,
            fee: 500,
            compound: false,
            oneshot: false,
            baseAmount: 1 ether
        });

        exchange.placeGridOrders(Currency.wrap(smaller), Currency.wrap(larger), param);
        vm.stopPrank();

        // Verify pair was created
        uint64 pairId = exchange.getPairIdByTokens(Currency.wrap(smaller), Currency.wrap(larger));
        assertTrue(pairId > 0);
    }

    /// @notice Test pair creation with equal priority tokens fails when base > quote
    function test_equalPriorityTokens_baseLarger_reverts() public {
        // Create two tokens with equal priority
        TestToken tokenA = new TestToken("Token A", "TKA", 18);
        TestToken tokenB = new TestToken("Token B", "TKB", 18);

        // Set equal priority
        vm.startPrank(exchange.owner());
        exchange.setQuoteToken(Currency.wrap(address(tokenA)), 100);
        exchange.setQuoteToken(Currency.wrap(address(tokenB)), 100);
        vm.stopPrank();

        // Determine which is smaller by address
        address smaller = address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB);
        address larger = address(tokenA) < address(tokenB) ? address(tokenB) : address(tokenA);

        // Mint tokens to maker
        TestToken(smaller).mint(maker, 1000 ether);
        TestToken(larger).mint(maker, 1000 ether);

        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;

        vm.startPrank(maker);
        IERC20Minimal(smaller).approve(address(exchange), type(uint256).max);
        IERC20Minimal(larger).approve(address(exchange), type(uint256).max);

        // base > quote should fail with "P1"
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: abi.encode(askPrice0, gap),
            bidData: "",
            askOrderCount: 1,
            bidOrderCount: 0,
            fee: 500,
            compound: false,
            oneshot: false,
            baseAmount: 1 ether
        });

        vm.expectRevert(IProtocolErrors.TokenOrderInvalid.selector);
        exchange.placeGridOrders(Currency.wrap(larger), Currency.wrap(smaller), param);
        vm.stopPrank();
    }

    // ============ ETH Refund Tests ============

    /// @notice Test ETH refund when overpaying for ask order fill
    /// @dev When filling ETH ask orders, taker receives WETH which they can unwrap
    function test_ethRefund_overpayAskFill() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint128 amt = 0.02 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        // Place ETH ask orders (ETH is base)
        _placeOrders(address(0), address(usdc), amt, 5, 0, askPrice0, 0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        uint256 takerWethBefore = weth.balanceOf(taker);

        // Taker fills ask order - pays USDC, receives WETH (not raw ETH)
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();

        uint256 takerWethAfter = weth.balanceOf(taker);

        // Taker should have received WETH
        assertEq(takerWethAfter - takerWethBefore, amt);
    }

    /// @notice Test ETH refund when overpaying for bid order fill
    function test_ethRefund_overpayBidFill() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 0.02 ether;
        uint128 bidOrderId = 0x0000000000000000000000000000001;

        // Place ETH bid orders (ETH is base, USDC is quote)
        _placeOrders(address(0), address(usdc), amt, 0, 5, 0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, bidOrderId);

        uint256 takerEthBefore = taker.balance;

        // Taker fills bid order - pays ETH, receives USDC
        vm.startPrank(taker);
        weth.deposit{value: amt}();
        weth.approve(address(exchange), amt);
        exchange.fillBidOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify taker paid ETH (via WETH)
        assertTrue(taker.balance < takerEthBefore);
    }

    /// @notice Test placing ETH grid orders with exact amount
    function test_ethGridOrders_exactAmount() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint128 amt = 0.1 ether;

        uint256 makerEthBefore = maker.balance;

        vm.startPrank(maker);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: abi.encode(askPrice0, gap),
            bidData: "",
            askOrderCount: 5,
            bidOrderCount: 0,
            fee: 500,
            compound: false,
            oneshot: false,
            baseAmount: amt
        });

        // Send exact ETH amount
        uint256 totalEth = uint256(amt) * 5;
        exchange.placeETHGridOrders{value: totalEth}(Currency.wrap(address(0)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        uint256 makerEthAfter = maker.balance;

        // Maker should have spent exactly totalEth
        assertEq(makerEthBefore - makerEthAfter, totalEth);
    }

    /// @notice Test placing ETH grid orders with excess amount (should refund)
    function test_ethGridOrders_excessAmount_refund() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint128 amt = 0.1 ether;

        uint256 makerEthBefore = maker.balance;

        vm.startPrank(maker);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: abi.encode(askPrice0, gap),
            bidData: "",
            askOrderCount: 5,
            bidOrderCount: 0,
            fee: 500,
            compound: false,
            oneshot: false,
            baseAmount: amt
        });

        // Send excess ETH
        uint256 totalEth = uint256(amt) * 5;
        uint256 excess = 0.5 ether;
        exchange.placeETHGridOrders{value: totalEth + excess}(
            Currency.wrap(address(0)), Currency.wrap(address(usdc)), param
        );
        vm.stopPrank();

        uint256 makerEthAfter = maker.balance;

        // Maker should have spent only totalEth (excess refunded)
        assertEq(makerEthBefore - makerEthAfter, totalEth);
    }

    // ============ Order Amount Overflow Tests ============

    /// @notice Test that total base amount overflow is caught
    function test_totalBaseAmount_overflow() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;

        // Amount that would overflow when multiplied by order count
        uint128 amt = type(uint128).max / 2;
        uint32 askCount = 3; // amt * 3 > type(uint128).max

        vm.startPrank(maker);
        sea.approve(address(exchange), type(uint256).max);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: abi.encode(askPrice0, gap),
            bidData: "",
            askOrderCount: askCount,
            bidOrderCount: 0,
            fee: 500,
            compound: false,
            oneshot: false,
            baseAmount: amt
        });

        vm.expectRevert();
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    // ============ Zero Order Count Tests ============

    /// @notice Test placing grid with zero ask and zero bid orders
    /// @dev The protocol allows zero order counts (creates empty grid)
    function test_zeroOrderCounts_allowed() public {
        // uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint128 amt = 1 ether;

        vm.startPrank(maker);
        sea.approve(address(exchange), type(uint256).max);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: "",
            bidData: "",
            askOrderCount: 0,
            bidOrderCount: 0,
            fee: 500,
            compound: false,
            oneshot: false,
            baseAmount: amt
        });

        // Zero order counts are allowed - creates an empty grid
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        assertEq(config.askOrderCount, 0);
        assertEq(config.bidOrderCount, 0);
    }

    // ============ Fill Amount Validation Tests ============

    /// @notice Test filling more than available amount
    function test_fillMoreThanAvailable() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Try to fill more than available
        uint128 fillAmt = amt + 1;

        vm.startPrank(taker);
        vm.expectRevert();
        exchange.fillAskOrder(gridOrderId, fillAmt, fillAmt, new bytes(0), 0);
        vm.stopPrank();
    }

    /// @notice Test filling zero amount
    function test_fillZeroAmount() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Try to fill zero amount
        vm.startPrank(taker);
        vm.expectRevert();
        exchange.fillAskOrder(gridOrderId, 0, 0, new bytes(0), 0);
        vm.stopPrank();
    }

    // ============ Multiple Grid Tests ============

    /// @notice Test creating multiple grids for same pair
    function test_multipleGridsSamePair() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        // Create first grid
        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        // Create second grid with different parameters
        uint256 askPrice1 = askPrice0 * 2;
        uint256 bidPrice1 = askPrice1 - gap;
        _placeOrdersBy(maker, address(sea), address(usdc), amt, 3, 3, askPrice1, bidPrice1, gap, false, 500);

        // Verify both grids exist
        IGridOrder.GridConfig memory config1 = exchange.getGridConfig(1);
        IGridOrder.GridConfig memory config2 = exchange.getGridConfig(2);

        assertEq(config1.askOrderCount, 5);
        assertEq(config1.bidOrderCount, 5);
        assertEq(config2.askOrderCount, 3);
        assertEq(config2.bidOrderCount, 3);
    }

    // ============ Slippage Protection Tests ============

    /// @notice Test slippage protection on fillAskOrder
    function test_slippageProtection_askOrder() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Set minAmt higher than what we're filling
        uint128 minAmt = amt + 1;

        vm.startPrank(taker);
        vm.expectRevert();
        exchange.fillAskOrder(gridOrderId, amt, minAmt, new bytes(0), 0);
        vm.stopPrank();
    }

    /// @notice Test slippage protection on fillBidOrder
    function test_slippageProtection_bidOrder() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 bidOrderId = 0x0000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, bidOrderId);

        // Set minAmt higher than what we're filling
        uint128 minAmt = amt + 1;

        vm.startPrank(taker);
        vm.expectRevert();
        exchange.fillBidOrder(gridOrderId, amt, minAmt, new bytes(0), 0);
        vm.stopPrank();
    }

    // ============ Oneshot Order Tests ============

    /// @notice Test oneshot orders behavior
    /// @dev Oneshot orders still flip but are marked as oneshot
    function test_oneshotOrders_behavior() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        // Place oneshot orders
        _placeOneshotOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Fill the ask order completely
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify order is filled and has oneshot flag
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        assertEq(order.amount, 0);
        assertTrue(order.oneshot);
        // Oneshot orders still have revAmount after fill (they flip like normal orders)
        // The difference is they can't be filled again from the reverse side
        assertTrue(order.revAmount > 0);
    }

    /// @notice Test oneshot ask order partial fill - verify protocol fee
    /// @dev For oneshot orders, all fee goes to protocol (lpFee = 0)
    function test_oneshotOrders_partialFill_askOrder_protocolFee() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12); // 0.002
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        // Place oneshot orders
        _placeOneshotOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Get initial protocol fee balance (protocol fees go to vault)
        uint256 vaultBalanceBefore = usdc.balanceOf(vault);

        // Partial fill - fill half of the order
        uint128 fillAmt = amt / 2;

        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Calculate expected fee
        // For oneshot: all fee goes to protocol, no LP fee
        uint32 oneshotFeeBps = exchange.getOneshotProtocolFeeBps();
        uint128 quoteVol = Lens.calcQuoteAmount(fillAmt, askPrice0, true);
        uint128 expectedProtocolFee = uint128((uint256(quoteVol) * uint256(oneshotFeeBps)) / 1000000);

        // Verify protocol fee was collected in vault
        uint256 vaultBalanceAfter = usdc.balanceOf(vault);
        assertEq(vaultBalanceAfter - vaultBalanceBefore, expectedProtocolFee, "Protocol fee mismatch for partial fill");

        // Verify order is partially filled
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        assertEq(order.amount, amt - fillAmt, "Order amount should be reduced by fill amount");
        assertTrue(order.oneshot, "Order should still be oneshot");
    }

    /// @notice Test oneshot ask order complete fill - verify protocol fee
    function test_oneshotOrders_completeFill_askOrder_protocolFee() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        // Place oneshot orders
        _placeOneshotOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Get initial protocol fee balance (protocol fees go to vault)
        uint256 vaultBalanceBefore = usdc.balanceOf(vault);

        // Complete fill
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Calculate expected fee
        uint32 oneshotFeeBps = exchange.getOneshotProtocolFeeBps();
        uint128 quoteVol = Lens.calcQuoteAmount(amt, askPrice0, true);
        uint128 expectedProtocolFee = uint128((uint256(quoteVol) * uint256(oneshotFeeBps)) / 1000000);

        // Verify protocol fee was collected in vault
        uint256 vaultBalanceAfter = usdc.balanceOf(vault);
        assertEq(vaultBalanceAfter - vaultBalanceBefore, expectedProtocolFee, "Protocol fee mismatch for complete fill");

        // Verify order is completely filled
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        assertEq(order.amount, 0, "Order amount should be 0 after complete fill");
        assertTrue(order.oneshot, "Order should still be oneshot");
        assertTrue(order.revAmount > 0, "Reverse amount should be set");
    }

    /// @notice Test oneshot bid order partial fill - verify protocol fee
    function test_oneshotOrders_partialFill_bidOrder_protocolFee() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 bidOrderId = 0x0000000000000000000000000000001;

        // Place oneshot orders
        _placeOneshotOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, bidOrderId);

        // Get initial protocol fee balance (for bid orders, fee is in quote token, goes to vault)
        uint256 vaultBalanceBefore = usdc.balanceOf(vault);

        // Partial fill - fill half of the order
        uint128 fillAmt = amt / 2;

        vm.startPrank(taker);
        exchange.fillBidOrder(gridOrderId, fillAmt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Calculate expected fee
        uint32 oneshotFeeBps = exchange.getOneshotProtocolFeeBps();
        uint128 filledVol = Lens.calcQuoteAmount(fillAmt, bidPrice0, false);
        uint128 expectedProtocolFee = uint128((uint256(filledVol) * uint256(oneshotFeeBps)) / 1000000);

        // Verify protocol fee was collected in vault
        uint256 vaultBalanceAfter = usdc.balanceOf(vault);
        assertEq(
            vaultBalanceAfter - vaultBalanceBefore, expectedProtocolFee, "Protocol fee mismatch for bid partial fill"
        );

        // Verify order is partially filled
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        assertTrue(order.oneshot, "Order should still be oneshot");
    }

    /// @notice Test oneshot bid order complete fill - verify protocol fee
    function test_oneshotOrders_completeFill_bidOrder_protocolFee() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 bidOrderId = 0x0000000000000000000000000000001;

        // Place oneshot orders
        _placeOneshotOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, bidOrderId);

        // Get initial protocol fee balance (protocol fees go to vault)
        uint256 vaultBalanceBefore = usdc.balanceOf(vault);

        // Complete fill
        vm.startPrank(taker);
        exchange.fillBidOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Calculate expected fee
        uint32 oneshotFeeBps = exchange.getOneshotProtocolFeeBps();
        uint128 filledVol = Lens.calcQuoteAmount(amt, bidPrice0, false);
        uint128 expectedProtocolFee = uint128((uint256(filledVol) * uint256(oneshotFeeBps)) / 1000000);

        // Verify protocol fee was collected in vault
        uint256 vaultBalanceAfter = usdc.balanceOf(vault);
        assertEq(
            vaultBalanceAfter - vaultBalanceBefore, expectedProtocolFee, "Protocol fee mismatch for bid complete fill"
        );

        // Verify order is completely filled
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        assertEq(order.amount, 0, "Order amount should be 0 after complete fill");
        assertTrue(order.oneshot, "Order should still be oneshot");
    }

    /// @notice Test oneshot orders use oneshotProtocolFeeBps instead of user-specified fee
    function test_oneshotOrders_usesOneshotProtocolFeeBps() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        // User specifies a different fee (1000 bps = 0.1%)
        uint32 userFee = 1000;

        // Place oneshot orders with user-specified fee
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: amt,
            fee: userFee, // User specifies 1000 bps
            compound: false,
            oneshot: true
        });

        vm.startPrank(maker);
        exchange.placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        // Verify grid uses oneshotProtocolFeeBps, not user-specified fee
        IGridOrder.GridConfig memory config = exchange.getGridConfig(1);
        uint32 oneshotFeeBps = exchange.getOneshotProtocolFeeBps();
        assertEq(config.fee, oneshotFeeBps, "Oneshot grid should use oneshotProtocolFeeBps");
        assertTrue(
            config.fee != userFee || oneshotFeeBps == userFee, "Fee should be overridden unless they happen to match"
        );
    }

    /// @notice Test that filled oneshot order cannot be filled from reverse side
    /// @dev When a oneshot order is completely filled, it's marked as canceled via completeOneShotOrder()
    function test_oneshotOrders_cannotFillReversed() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        // Place oneshot orders
        _placeOneshotOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Fill the ask order completely
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify order has flipped (has revAmount)
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        assertTrue(order.revAmount > 0, "Order should have reverse amount");

        // Try to fill from reverse side (bid) - should revert with OrderCanceled
        // because completeOneShotOrder() marks the order as GRID_STATUS_CANCELED
        vm.startPrank(taker);
        vm.expectRevert(IOrderErrors.OrderCanceled.selector);
        exchange.fillBidOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();
    }

    /// @notice Test that partially filled oneshot order reverts with FillReversedOneShotOrder
    /// @dev When a oneshot order is only partially filled, it's not canceled yet, so FillReversedOneShotOrder is thrown
    function test_oneshotOrders_partialFill_cannotFillReversed() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        // Place oneshot orders
        _placeOneshotOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Partially fill the ask order (only half)
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt / 2, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify order is partially filled (still has amount remaining)
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        assertEq(order.amount, amt / 2, "Order should be partially filled");
        assertTrue(order.revAmount > 0, "Order should have reverse amount");

        // Try to fill from reverse side (bid) - should revert with FillReversedOneShotOrder
        // because the order is not fully filled yet, so it's not canceled
        vm.startPrank(taker);
        vm.expectRevert(IOrderErrors.FillReversedOneShotOrder.selector);
        exchange.fillBidOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();
    }

    /// @notice Test oneshot order LP fee is always 0
    function test_oneshotOrders_lpFeeIsZero() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        // Place oneshot orders
        _placeOneshotOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Get vault balance before (protocol fees go to vault)
        uint256 vaultBalanceBefore = usdc.balanceOf(vault);

        // Fill the ask order
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Calculate what the total fee is
        uint32 oneshotFeeBps = exchange.getOneshotProtocolFeeBps();
        uint128 quoteVol = Lens.calcQuoteAmount(amt, askPrice0, true);
        uint128 totalFee = uint128((uint256(quoteVol) * uint256(oneshotFeeBps)) / 1000000);
        // For normal orders: lpFee = totalFee - protocolFee = totalFee - (totalFee >> 2) = 75% of totalFee
        // For oneshot: lpFee = 0, protocolFee = 100% of totalFee

        // Verify protocol got all the fee (sent to vault)
        uint256 vaultBalanceAfter = usdc.balanceOf(vault);
        assertEq(vaultBalanceAfter - vaultBalanceBefore, totalFee, "Protocol should receive all fee for oneshot orders");
    }

    /// @notice Test setOneshotProtocolFeeBps and getOneshotProtocolFeeBps
    function test_oneshotProtocolFeeBps_setAndGet() public {
        // Get initial value
        uint32 initialFeeBps = exchange.getOneshotProtocolFeeBps();
        assertEq(initialFeeBps, 500, "Initial oneshot fee should be 500 bps");

        // Set new value (only owner can do this)
        uint32 newFeeBps = 1000; // 0.1%
        exchange.setOneshotProtocolFeeBps(newFeeBps);

        // Verify new value
        uint32 updatedFeeBps = exchange.getOneshotProtocolFeeBps();
        assertEq(updatedFeeBps, newFeeBps, "Oneshot fee should be updated");
    }

    /// @notice Test setOneshotProtocolFeeBps reverts for invalid fee
    function test_oneshotProtocolFeeBps_revertInvalidFee() public {
        // Try to set fee below MIN_FEE
        vm.expectRevert(IOrderErrors.InvalidGridFee.selector);
        exchange.setOneshotProtocolFeeBps(99); // MIN_FEE is 100

        // Try to set fee above MAX_FEE
        vm.expectRevert(IOrderErrors.InvalidGridFee.selector);
        exchange.setOneshotProtocolFeeBps(100001); // MAX_FEE is 100000
    }

    /// @notice Test that oneshot grid fee cannot be modified
    function test_oneshotOrders_cannotModifyFee() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;

        // Place oneshot orders
        _placeOneshotOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        // Try to modify fee - should revert
        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.CannotModifyOneshotFee.selector);
        exchange.modifyGridFee(1, 1000);
        vm.stopPrank();
    }

    /// @notice Test multiple partial fills on oneshot order accumulate correct protocol fees
    function test_oneshotOrders_multiplePartialFills_protocolFee() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        // Place oneshot orders
        _placeOneshotOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Get initial protocol fee balance (protocol fees go to vault)
        uint256 vaultBalanceBefore = usdc.balanceOf(vault);

        uint32 oneshotFeeBps = exchange.getOneshotProtocolFeeBps();
        uint128 totalExpectedFee = 0;

        // First partial fill - 25%
        uint128 fillAmt1 = amt / 4;
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, fillAmt1, 0, new bytes(0), 0);
        vm.stopPrank();

        uint128 quoteVol1 = Lens.calcQuoteAmount(fillAmt1, askPrice0, true);
        totalExpectedFee += uint128((uint256(quoteVol1) * uint256(oneshotFeeBps)) / 1000000);

        // Second partial fill - 25%
        uint128 fillAmt2 = amt / 4;
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, fillAmt2, 0, new bytes(0), 0);
        vm.stopPrank();

        uint128 quoteVol2 = Lens.calcQuoteAmount(fillAmt2, askPrice0, true);
        totalExpectedFee += uint128((uint256(quoteVol2) * uint256(oneshotFeeBps)) / 1000000);

        // Third partial fill - remaining 50%
        uint128 fillAmt3 = amt / 2;
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, fillAmt3, 0, new bytes(0), 0);
        vm.stopPrank();

        uint128 quoteVol3 = Lens.calcQuoteAmount(fillAmt3, askPrice0, true);
        totalExpectedFee += uint128((uint256(quoteVol3) * uint256(oneshotFeeBps)) / 1000000);

        // Verify total protocol fee (sent to vault)
        uint256 vaultBalanceAfter = usdc.balanceOf(vault);
        assertEq(
            vaultBalanceAfter - vaultBalanceBefore,
            totalExpectedFee,
            "Total protocol fee mismatch for multiple partial fills"
        );

        // Verify order is completely filled
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        assertEq(order.amount, 0, "Order should be completely filled");
    }

    // ============ Compound Order Tests ============

    /// @notice Test compound orders accumulate profits
    function test_compoundOrders() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        // Place compound orders
        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, true, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);

        // Fill the ask order
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();

        // Verify order has compound flag
        IGridOrder.OrderInfo memory order = exchange.getGridOrder(gridOrderId);
        assertTrue(order.compound);
    }
}

/// @notice Test token for equal priority tests
contract TestToken is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol, decimals) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
