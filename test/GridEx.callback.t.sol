// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {GridExBaseTest} from "./GridExBase.t.sol";
import {IGridCallback} from "../src/interfaces/IGridCallback.sol";
import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {IGridStrategy} from "../src/interfaces/IGridStrategy.sol";
import {IERC20Minimal} from "../src/interfaces/IERC20Minimal.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";

/// @title GridExCallbackTest
/// @notice Tests for callback pattern with various receiver behaviors
contract GridExCallbackTest is GridExBaseTest {
    MaliciousCallback public maliciousCallback;
    ReentrantCallback public reentrantCallback;
    InsufficientPayCallback public insufficientCallback;
    ValidCallback public validCallback;
    CancelDuringCallback public cancelDuringCallback;
    PlaceDuringCallback public placeDuringCallback;

    function setUp() public override {
        super.setUp();

        maliciousCallback = new MaliciousCallback();
        reentrantCallback = new ReentrantCallback(address(exchange));
        insufficientCallback = new InsufficientPayCallback();
        validCallback = new ValidCallback();
        cancelDuringCallback = new CancelDuringCallback(address(exchange));
        placeDuringCallback = new PlaceDuringCallback(address(exchange));

        // Fund the callback contracts
        // forge-lint: disable-next-line
        sea.transfer(address(maliciousCallback), 1000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(address(maliciousCallback), 1000_000_000);

        // forge-lint: disable-next-line
        sea.transfer(address(reentrantCallback), 1000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(address(reentrantCallback), 1000_000_000);

        // forge-lint: disable-next-line
        sea.transfer(address(insufficientCallback), 1000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(address(insufficientCallback), 1000_000_000);

        // forge-lint: disable-next-line
        sea.transfer(address(validCallback), 1000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(address(validCallback), 1000_000_000);

        // forge-lint: disable-next-line
        sea.transfer(address(cancelDuringCallback), 1000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(address(cancelDuringCallback), 1000_000_000);

        // forge-lint: disable-next-line
        sea.transfer(address(placeDuringCallback), 1000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(address(placeDuringCallback), 1000_000_000);

        // Approve exchange for callback contracts
        vm.startPrank(address(maliciousCallback));
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(reentrantCallback));
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(insufficientCallback));
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(validCallback));
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(cancelDuringCallback));
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(placeDuringCallback));
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        vm.stopPrank();
    }

    // ============ Valid Callback Tests ============

    /// @notice Test valid callback for fillAskOrder
    function test_callback_validFillAsk() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 orderId = 0x8000;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 gridOrderId = toGridOrderId(1, orderId);

        // Set up valid callback
        validCallback.setExchange(address(exchange));

        uint256 seaBefore = sea.balanceOf(address(validCallback));

        vm.prank(address(validCallback));
        exchange.fillAskOrder(gridOrderId, amt, 0, abi.encode("callback"), 0);

        uint256 seaAfter = sea.balanceOf(address(validCallback));

        // Callback should have received base tokens
        assertEq(seaAfter - seaBefore, amt);
    }

    /// @notice Test valid callback for fillBidOrder
    function test_callback_validFillBid() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 bidOrderId = 1;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 gridOrderId = toGridOrderId(1, bidOrderId);

        // Set up valid callback
        validCallback.setExchange(address(exchange));

        uint256 usdcBefore = usdc.balanceOf(address(validCallback));

        vm.prank(address(validCallback));
        exchange.fillBidOrder(gridOrderId, amt, 0, abi.encode("callback"), 0);

        uint256 usdcAfter = usdc.balanceOf(address(validCallback));

        // Callback should have received quote tokens (minus fees)
        assertTrue(usdcAfter > usdcBefore);
    }

    // ============ Malicious Callback Tests ============

    /// @notice Test callback that doesn't pay enough reverts
    function test_callback_insufficientPayment() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 orderId = 0x8000;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 gridOrderId = toGridOrderId(1, orderId);

        // Insufficient callback pays less than required
        insufficientCallback.setPayPercentage(50); // Only pay 50%

        vm.prank(address(insufficientCallback));
        vm.expectRevert();
        exchange.fillAskOrder(gridOrderId, amt, 0, abi.encode("callback"), 0);
    }

    /// @notice Test callback that pays nothing reverts
    function test_callback_noPayment() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 orderId = 0x8000;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 gridOrderId = toGridOrderId(1, orderId);

        // Insufficient callback pays nothing
        insufficientCallback.setPayPercentage(0);

        vm.prank(address(insufficientCallback));
        vm.expectRevert();
        exchange.fillAskOrder(gridOrderId, amt, 0, abi.encode("callback"), 0);
    }

    /// @notice Test re-entry from flash-swap callback to fill a different ask order
    /// @dev With depth-counting reentrancy guard, callbacks can re-enter to fill
    ///      different orders (cross-order arbitrage). The inner fill targets a different
    ///      order than the outer fill.
    function test_callback_reentrantFillAsk() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 orderId = 0x8000;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 outerOrderId = toGridOrderId(1, orderId);
        uint64 innerOrderId = toGridOrderId(1, orderId + 1); // different order

        // Set up reentrant callback to fill a DIFFERENT ask order during callback
        reentrantCallback.setReentryTarget(innerOrderId, amt, true);

        uint256 seaBefore = sea.balanceOf(address(reentrantCallback));

        // The outer call succeeds, and the inner re-entry also succeeds
        vm.prank(address(reentrantCallback));
        exchange.fillAskOrder(outerOrderId, amt, 0, abi.encode("reenter"), 0);

        // Verify that re-entry was performed
        assertTrue(reentrantCallback.hasReentered(), "Re-entry should have been performed");
        // Verify that re-entry succeeded
        assertTrue(reentrantCallback.reentrySucceeded(), "Re-entry should have succeeded");

        uint256 seaAfter = sea.balanceOf(address(reentrantCallback));
        // Callback received base tokens from both outer and inner fills
        assertEq(seaAfter - seaBefore, 2 * amt, "Should receive base tokens from both fills");
    }

    /// @notice Test re-entry from flash-swap callback to fill a different bid order
    /// @dev With depth-counting reentrancy guard, callbacks can re-enter to fill
    ///      different orders (cross-order arbitrage).
    function test_callback_reentrantFillBid() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 bidOrderId = 1;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 outerOrderId = toGridOrderId(1, bidOrderId);
        uint64 innerOrderId = toGridOrderId(1, bidOrderId + 1); // different order

        // Set up reentrant callback to fill a DIFFERENT bid order during callback
        reentrantCallback.setReentryTarget(innerOrderId, amt, false);

        uint256 usdcBefore = usdc.balanceOf(address(reentrantCallback));

        // The outer call succeeds, and the inner re-entry also succeeds
        vm.prank(address(reentrantCallback));
        exchange.fillBidOrder(outerOrderId, amt, 0, abi.encode("reenter"), 0);

        // Verify that re-entry was performed and succeeded
        assertTrue(reentrantCallback.hasReentered(), "Re-entry should have been performed");
        assertTrue(reentrantCallback.reentrySucceeded(), "Re-entry should have succeeded");

        uint256 usdcAfter = usdc.balanceOf(address(reentrantCallback));
        // Callback received quote tokens from both outer and inner fills
        assertTrue(usdcAfter > usdcBefore, "Should receive quote tokens from both fills");
    }

    /// @notice Test that outer call fails when callback re-enters with a bid fill
    ///         and doesn't pay for the outer ask fill
    /// @dev The inner bid fill sends USDC OUT of the exchange, reducing the exchange's
    ///      USDC balance. The outer ask fill's balance check then fails because:
    ///      - balanceBefore + inAmt > balanceAfter (USDC was drained by inner bid fill)
    ///      Even though re-entry succeeds, the outer call still requires payment.
    function test_callback_reentrantFillAsk_failsWithoutPayment() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 askOrderId = 0x8000;
        uint16 bidOrderId = 0;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 outerOrderId = toGridOrderId(1, askOrderId);
        // Inner call fills a BID order — this sends USDC out of the exchange
        uint64 innerOrderId = toGridOrderId(1, bidOrderId);

        // Use a callback that pays for the inner re-entry but NOT for the outer call
        ReentrantNoPayCallback noPayCallback = new ReentrantNoPayCallback(address(exchange));
        // forge-lint: disable-next-line
        sea.transfer(address(noPayCallback), 1000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(address(noPayCallback), 1000_000_000);

        vm.startPrank(address(noPayCallback));
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        vm.stopPrank();

        // Inner call is a BID fill (isAsk=false) — pays SEA, receives USDC
        noPayCallback.setReentryTarget(innerOrderId, amt, false);

        // This should revert because:
        // 1. Inner bid fill sends USDC out of exchange (reducing USDC balance)
        // 2. Outer callback doesn't pay USDC for the outer ask fill
        // 3. Outer ask fill's balance check fails
        vm.prank(address(noPayCallback));
        vm.expectRevert();
        exchange.fillAskOrder(outerOrderId, amt, 0, abi.encode("reenter"), 0);
    }

    /// @notice Test callback that reverts
    function test_callback_reverts() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 orderId = 0x8000;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 gridOrderId = toGridOrderId(1, orderId);

        // Malicious callback will revert
        maliciousCallback.setShouldRevert(true);

        vm.prank(address(maliciousCallback));
        vm.expectRevert();
        exchange.fillAskOrder(gridOrderId, amt, 0, abi.encode("callback"), 0);
    }

    /// @notice Test callback with empty data (no callback triggered)
    function test_noCallback_emptyData() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 orderId = 0x8000;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 gridOrderId = toGridOrderId(1, orderId);

        uint256 seaBefore = sea.balanceOf(taker);

        // Empty data means no callback
        vm.startPrank(taker);
        exchange.fillAskOrder(gridOrderId, amt, 0, new bytes(0), 0);
        vm.stopPrank();

        uint256 seaAfter = sea.balanceOf(taker);
        assertEq(seaAfter - seaBefore, amt);
    }

    // ============ Multiple Order Callback Tests ============

    /// @notice Test callback for fillAskOrders (multiple orders)
    function test_callback_fillAskOrders() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 orderId = 0x8000;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64[] memory idList = new uint64[](3);
        idList[0] = toGridOrderId(1, orderId);
        idList[1] = toGridOrderId(1, orderId + 1);
        idList[2] = toGridOrderId(1, orderId + 2);

        uint128[] memory amtList = new uint128[](3);
        amtList[0] = amt;
        amtList[1] = amt;
        amtList[2] = amt;

        validCallback.setExchange(address(exchange));

        uint256 seaBefore = sea.balanceOf(address(validCallback));

        vm.prank(address(validCallback));
        exchange.fillAskOrders(1, idList, amtList, 0, 0, abi.encode("callback"), 0);

        uint256 seaAfter = sea.balanceOf(address(validCallback));

        // Should receive 3 * amt base tokens
        assertEq(seaAfter - seaBefore, 3 * amt);
    }

    /// @notice Test callback for fillBidOrders (multiple orders)
    function test_callback_fillBidOrders() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 bidOrderId = 1;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64[] memory idList = new uint64[](3);
        idList[0] = toGridOrderId(1, bidOrderId);
        idList[1] = toGridOrderId(1, bidOrderId + 1);
        idList[2] = toGridOrderId(1, bidOrderId + 2);

        uint128[] memory amtList = new uint128[](3);
        amtList[0] = amt;
        amtList[1] = amt;
        amtList[2] = amt;

        validCallback.setExchange(address(exchange));

        uint256 usdcBefore = usdc.balanceOf(address(validCallback));

        vm.prank(address(validCallback));
        exchange.fillBidOrders(1, idList, amtList, 0, 0, abi.encode("callback"), 0);

        uint256 usdcAfter = usdc.balanceOf(address(validCallback));

        // Should receive quote tokens
        assertTrue(usdcAfter > usdcBefore);
    }

    /// @notice Test cross-order arbitrage: fill ask in callback of fill bid
    /// @dev Demonstrates the primary use case: buy low (fill bid) and sell high (fill ask)
    ///      in a single atomic transaction via flash-swap callback
    function test_callback_crossOrderArbitrage() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 askOrderId = 0x8000;
        uint16 bidOrderId = 0;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 askGridOrderId = toGridOrderId(1, askOrderId);
        uint64 bidGridOrderId = toGridOrderId(1, bidOrderId);

        // Create an arbitrage callback that fills a bid order inside an ask order callback
        ArbitrageCallback arbCallback = new ArbitrageCallback(address(exchange));
        // forge-lint: disable-next-line
        sea.transfer(address(arbCallback), 1000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(address(arbCallback), 1000_000_000);

        vm.startPrank(address(arbCallback));
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        vm.stopPrank();

        // Set up: when filling the ask order, the callback will fill a bid order
        arbCallback.setArbitrageTarget(bidGridOrderId, amt);

        uint256 seaBefore = sea.balanceOf(address(arbCallback));
        uint256 usdcBefore = usdc.balanceOf(address(arbCallback));

        // Fill ask order (buy base with quote) — callback will fill bid order (sell base for quote)
        vm.prank(address(arbCallback));
        exchange.fillAskOrder(askGridOrderId, amt, 0, abi.encode("arbitrage"), 0);

        uint256 seaAfter = sea.balanceOf(address(arbCallback));
        uint256 usdcAfter = usdc.balanceOf(address(arbCallback));

        // The arbitrage callback received base from ask fill, used it to fill bid,
        // and received quote from bid fill. Net effect depends on price spread.
        assertTrue(arbCallback.arbitrageExecuted(), "Arbitrage should have been executed");

        // Log the net position change for debugging
        // forge-lint: disable-next-line(unsafe-typecast)
        emit log_named_int("SEA change", int256(seaAfter) - int256(seaBefore));
        // forge-lint: disable-next-line(unsafe-typecast)
        emit log_named_int("USDC change", int256(usdcAfter) - int256(usdcBefore));
    }

    // ============ Cross-Type Fill Callback Tests ============

    /// @notice Test fillAskOrder callback that calls fillBidOrder internally
    /// @dev Scenario: Taker fills an ask order (buys SEA with USDC). In the callback,
    ///      the taker receives SEA and immediately sells it via fillBidOrder to get USDC back.
    ///      This is a flash-swap arbitrage: buy base cheap via ask, sell base via bid for quote.
    ///      fillAskOrder callback: inToken=USDC, outToken=SEA, must pay USDC
    ///      Inner fillBidOrder: pays SEA (received from outer), gets USDC
    ///      The inner bid fill's USDC output can offset the outer ask fill's USDC cost.
    function test_callback_fillAskCallsFillBid() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 askOrderId = 0x8000;
        uint16 bidOrderId = 0;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 askGridOrderId = toGridOrderId(1, askOrderId);
        uint64 bidGridOrderId = toGridOrderId(1, bidOrderId);

        // Create the callback contract
        AskCallsBidCallback askBidCb = new AskCallsBidCallback(address(exchange));
        // forge-lint: disable-next-line
        sea.transfer(address(askBidCb), 1000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(address(askBidCb), 1000_000_000);

        vm.startPrank(address(askBidCb));
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        vm.stopPrank();

        // Configure: outer fillAskOrder callback will call fillBidOrder
        askBidCb.setTarget(bidGridOrderId, amt);

        uint256 seaBefore = sea.balanceOf(address(askBidCb));
        uint256 usdcBefore = usdc.balanceOf(address(askBidCb));

        // Execute: fill ask order with callback
        vm.prank(address(askBidCb));
        exchange.fillAskOrder(askGridOrderId, amt, 0, abi.encode("ask-calls-bid"), 0);

        uint256 seaAfter = sea.balanceOf(address(askBidCb));
        uint256 usdcAfter = usdc.balanceOf(address(askBidCb));

        // Verify the inner bid fill was executed
        assertTrue(askBidCb.innerFillExecuted(), "Inner fillBidOrder should have been executed");

        // The outer ask fill: received SEA, paid USDC
        // The inner bid fill: paid SEA, received USDC
        // Net SEA change should be 0 (received from ask, paid to bid)
        assertEq(seaAfter, seaBefore, "SEA should be net zero (received from ask, paid to bid)");

        // Net USDC change: received from bid fill minus paid for ask fill
        // Since ask price > bid price (spread), the taker loses USDC on the spread + fees
        assertTrue(usdcBefore > usdcAfter, "USDC should decrease due to spread + fees");

        // Log the net position change
        // forge-lint: disable-next-line(unsafe-typecast)
        emit log_named_int("SEA net change", int256(seaAfter) - int256(seaBefore));
        // forge-lint: disable-next-line(unsafe-typecast)
        emit log_named_int("USDC net change", int256(usdcAfter) - int256(usdcBefore));
    }

    /// @notice Test fillBidOrder callback that calls fillAskOrder internally
    /// @dev Scenario: Taker fills a bid order (sells SEA for USDC). In the callback,
    ///      the taker receives USDC and immediately buys SEA via fillAskOrder.
    ///      This is a reverse flash-swap: sell base via bid for quote, buy base via ask with quote.
    ///      fillBidOrder callback: inToken=SEA, outToken=USDC, must pay SEA
    ///      Inner fillAskOrder: pays USDC (received from outer), gets SEA
    ///      The inner ask fill's SEA output can offset the outer bid fill's SEA cost.
    function test_callback_fillBidCallsFillAsk() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 askOrderId = 0x8000;
        uint16 bidOrderId = 0;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 askGridOrderId = toGridOrderId(1, askOrderId);
        uint64 bidGridOrderId = toGridOrderId(1, bidOrderId);

        // Create the reverse arbitrage callback contract
        BidCallsAskCallback bidAskCb = new BidCallsAskCallback(address(exchange));
        // forge-lint: disable-next-line
        sea.transfer(address(bidAskCb), 1000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(address(bidAskCb), 1000_000_000);

        vm.startPrank(address(bidAskCb));
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        vm.stopPrank();

        // Configure: outer fillBidOrder callback will call fillAskOrder
        bidAskCb.setTarget(askGridOrderId, amt);

        uint256 seaBefore = sea.balanceOf(address(bidAskCb));
        uint256 usdcBefore = usdc.balanceOf(address(bidAskCb));

        // Execute: fill bid order with callback
        vm.prank(address(bidAskCb));
        exchange.fillBidOrder(bidGridOrderId, amt, 0, abi.encode("bid-calls-ask"), 0);

        uint256 seaAfter = sea.balanceOf(address(bidAskCb));
        uint256 usdcAfter = usdc.balanceOf(address(bidAskCb));

        // Verify the inner ask fill was executed
        assertTrue(bidAskCb.innerFillExecuted(), "Inner fillAskOrder should have been executed");

        // The outer bid fill: must pay SEA (filledAmt=1e18), receives USDC (outAmt)
        // The inner ask fill: receives SEA (filledAmt=1e18), must pay USDC (inAmt)
        //
        // Due to the balance-checking compensation mechanism:
        //   - Inner ask sends 1e18 SEA out of exchange to callback
        //   - Outer bid checks exchange's SEA balance increased by filledAmt (1e18)
        //   - So outer callback must pay filledAmt + innerOutAmt = 1e18 + 1e18 = 2e18 SEA
        //   - Callback received 1e18 SEA from inner ask, paid 2e18 SEA to outer bid
        //   - Net SEA loss = 1e18 (the outer bid's filledAmt)
        //
        // Net USDC: received outAmt from bid, paid inAmt for ask
        //   bid outAmt = vol - lpFee - protocolFee (at lower bid price)
        //   ask inAmt = vol + lpFee + protocolFee (at higher ask price)
        //   So USDC also decreases
        assertEq(seaBefore - seaAfter, amt, "SEA should decrease by filledAmt due to compensation mechanism");

        // Net USDC: bid provides less USDC than ask costs (spread + fees on both sides)
        assertTrue(usdcBefore > usdcAfter, "USDC should decrease due to spread + fees on both sides");

        // Log the net position change
        // forge-lint: disable-next-line(unsafe-typecast)
        emit log_named_int("SEA net change", int256(seaAfter) - int256(seaBefore));
        // forge-lint: disable-next-line(unsafe-typecast)
        emit log_named_int("USDC net change", int256(usdcAfter) - int256(usdcBefore));
    }

    /// @notice Test insufficient payment in multi-order callback
    function test_callback_fillAskOrders_insufficientPayment() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 orderId = 0x8000;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64[] memory idList = new uint64[](3);
        idList[0] = toGridOrderId(1, orderId);
        idList[1] = toGridOrderId(1, orderId + 1);
        idList[2] = toGridOrderId(1, orderId + 2);

        uint128[] memory amtList = new uint128[](3);
        amtList[0] = amt;
        amtList[1] = amt;
        amtList[2] = amt;

        insufficientCallback.setPayPercentage(50);

        vm.prank(address(insufficientCallback));
        vm.expectRevert();
        exchange.fillAskOrders(1, idList, amtList, 0, 0, abi.encode("callback"), 0);
    }

    // ============ Cancel-During-Callback Tests ============

    /// @notice Test that cancelGrid is blocked during a flash-swap callback
    /// @dev The cancel path uses _guardNoReentry() which reverts when depth > 0
    function test_callback_cancelDuringFill_reverts() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 orderId = 0x8000;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 gridOrderId = toGridOrderId(1, orderId);

        // Configure the callback to attempt cancelGrid during the fill callback
        cancelDuringCallback.setCancelTarget(1); // gridId = 1

        vm.prank(address(cancelDuringCallback));
        exchange.fillAskOrder(gridOrderId, amt, 0, abi.encode("cancel-attempt"), 0);

        // The cancel attempt inside the callback should have been blocked
        assertTrue(cancelDuringCallback.cancelAttempted(), "Cancel should have been attempted");
        assertFalse(cancelDuringCallback.cancelSucceeded(), "Cancel should have been blocked by reentrancy guard");
    }

    /// @notice Test that withdrawGridProfits is blocked during a flash-swap callback
    function test_callback_withdrawDuringFill_reverts() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 orderId = 0x8000;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 gridOrderId = toGridOrderId(1, orderId);

        // Configure the callback to attempt withdrawGridProfits during the fill callback
        cancelDuringCallback.setWithdrawTarget(1); // gridId = 1

        vm.prank(address(cancelDuringCallback));
        exchange.fillAskOrder(gridOrderId, amt, 0, abi.encode("withdraw-attempt"), 0);

        // The withdraw attempt inside the callback should have been blocked
        assertTrue(cancelDuringCallback.cancelAttempted(), "Withdraw should have been attempted");
        assertFalse(cancelDuringCallback.cancelSucceeded(), "Withdraw should have been blocked by reentrancy guard");
    }

    // ============ Place-During-Callback Tests ============

    /// @notice Test that placeGridOrders is blocked during a flash-swap callback
    /// @dev The place path uses _guardNoReentry() which reverts when depth > 0
    function test_callback_placeDuringFill_reverts() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint16 orderId = 0x8000;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint64 gridOrderId = toGridOrderId(1, orderId);

        // Configure the callback to attempt placeGridOrders during the fill callback
        placeDuringCallback.setPlaceTarget(address(sea), address(usdc), address(linear), askPrice0, bidPrice0, gap, amt);

        vm.prank(address(placeDuringCallback));
        exchange.fillAskOrder(gridOrderId, amt, 0, abi.encode("place-attempt"), 0);

        // The place attempt inside the callback should have been blocked
        assertTrue(placeDuringCallback.placeAttempted(), "Place should have been attempted");
        assertFalse(placeDuringCallback.placeSucceeded(), "Place should have been blocked by reentrancy guard");
    }
}

/// @notice Malicious callback that can revert on demand
contract MaliciousCallback is IGridCallback {
    bool public shouldRevert;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function gridFillCallback(address inToken, address, uint128 inAmt, uint128, bytes calldata) external override {
        if (shouldRevert) {
            revert("Malicious revert");
        }
        // Pay the required amount
        // forge-lint: disable-next-line
        IERC20Minimal(inToken).transfer(msg.sender, inAmt);
    }
}

/// @notice Callback that attempts reentrancy — now expects re-entry to succeed
/// @dev With depth-counting reentrancy guard, re-entry to fill different orders is allowed
contract ReentrantCallback is IGridCallback {
    address public exchange;
    uint256 public targetOrderId;
    uint128 public targetAmt;
    bool public isAsk;
    bool public hasReentered;
    bool public reentrySucceeded;

    constructor(address _exchange) {
        exchange = _exchange;
    }

    function setReentryTarget(uint256 _orderId, uint128 _amt, bool _isAsk) external {
        targetOrderId = _orderId;
        targetAmt = _amt;
        isAsk = _isAsk;
        hasReentered = false;
        reentrySucceeded = false;
    }

    function gridFillCallback(address inToken, address, uint128 inAmt, uint128, bytes calldata) external override {
        if (!hasReentered) {
            hasReentered = true;
            // Attempt re-entry to fill a different order
            bool success;
            if (isAsk) {
                (success,) = exchange.call(
                    abi.encodeWithSignature(
                        "fillAskOrder(uint64,uint128,uint128,bytes,uint32)",
                        targetOrderId,
                        targetAmt,
                        uint128(0),
                        "",
                        uint32(0)
                    )
                );
            } else {
                (success,) = exchange.call(
                    abi.encodeWithSignature(
                        "fillBidOrder(uint64,uint128,uint128,bytes,uint32)",
                        targetOrderId,
                        targetAmt,
                        uint128(0),
                        "",
                        uint32(0)
                    )
                );
            }
            require(success, "Re-entry should succeed");
            reentrySucceeded = true;
        }
        // Pay the required amount for this (outer or inner) call
        // forge-lint: disable-next-line
        IERC20Minimal(inToken).transfer(msg.sender, inAmt);
    }
}

/// @notice Callback that pays less than required
contract InsufficientPayCallback is IGridCallback {
    uint256 public payPercentage = 100;

    function setPayPercentage(uint256 _percentage) external {
        payPercentage = _percentage;
    }

    function gridFillCallback(address inToken, address, uint128 inAmt, uint128, bytes calldata) external override {
        // Pay only a percentage of required amount
        uint128 payAmt = uint128((uint256(inAmt) * payPercentage) / 100);
        if (payAmt > 0) {
            // forge-lint: disable-next-line
            IERC20Minimal(inToken).transfer(msg.sender, payAmt);
        }
    }
}

/// @notice Valid callback that pays correctly
contract ValidCallback is IGridCallback {
    address public exchange;

    function setExchange(address _exchange) external {
        exchange = _exchange;
    }

    function gridFillCallback(address inToken, address, uint128 inAmt, uint128, bytes calldata) external override {
        // Pay the full required amount
        // forge-lint: disable-next-line
        IERC20Minimal(inToken).transfer(msg.sender, inAmt);
    }
}

/// @notice Callback that attempts reentrancy but does NOT pay for the outer call
/// @dev With depth-counting guard, re-entry succeeds. But this callback deliberately
///      does not pay for the outer call, so the outer fill should revert on balance check.
///      The inner call's callback (this same contract, re-entered) DOES pay.
contract ReentrantNoPayCallback is IGridCallback {
    address public exchange;
    uint256 public targetOrderId;
    uint128 public targetAmt;
    bool public isAsk;
    bool public reentrancySucceeded;
    bool private _isInnerCall;

    constructor(address _exchange) {
        exchange = _exchange;
    }

    function setReentryTarget(uint256 _orderId, uint128 _amt, bool _isAsk) external {
        targetOrderId = _orderId;
        targetAmt = _amt;
        isAsk = _isAsk;
        reentrancySucceeded = false;
        _isInnerCall = false;
    }

    function gridFillCallback(address inToken, address, uint128 inAmt, uint128, bytes calldata) external override {
        if (_isInnerCall) {
            // Inner call: pay normally so the inner fill succeeds
            // forge-lint: disable-next-line
            IERC20Minimal(inToken).transfer(msg.sender, inAmt);
            return;
        }

        // Outer call: attempt re-entry, then deliberately do NOT pay
        _isInnerCall = true;
        bool success;
        if (isAsk) {
            (success,) = exchange.call(
                abi.encodeWithSignature(
                    "fillAskOrder(uint64,uint128,uint128,bytes,uint32)",
                    targetOrderId,
                    targetAmt,
                    uint128(0),
                    abi.encode("inner"),
                    uint32(0)
                )
            );
        } else {
            (success,) = exchange.call(
                abi.encodeWithSignature(
                    "fillBidOrder(uint64,uint128,uint128,bytes,uint32)",
                    targetOrderId,
                    targetAmt,
                    uint128(0),
                    abi.encode("inner"),
                    uint32(0)
                )
            );
        }

        if (success) {
            reentrancySucceeded = true;
        }
        // Deliberately do NOT pay for the outer call — outer fill should revert
    }
}

/// @notice Callback for cross-order arbitrage: fills a bid order inside an ask order callback
/// @dev Demonstrates buying base tokens via ask fill, then selling them via bid fill
///      in a single atomic transaction
contract ArbitrageCallback is IGridCallback {
    address public exchange;
    uint256 public bidOrderId;
    uint128 public bidAmt;
    bool public arbitrageExecuted;
    bool private _isInnerCall;
    uint128 private _innerOutAmt;

    constructor(address _exchange) {
        exchange = _exchange;
    }

    function setArbitrageTarget(uint256 _bidOrderId, uint128 _bidAmt) external {
        bidOrderId = _bidOrderId;
        bidAmt = _bidAmt;
        arbitrageExecuted = false;
        _isInnerCall = false;
        _innerOutAmt = 0;
    }

    function gridFillCallback(address inToken, address, uint128 inAmt, uint128 outAmt, bytes calldata)
        external
        override
    {
        if (_isInnerCall) {
            // Inner call (bid fill callback): pay base tokens to exchange
            _innerOutAmt = outAmt;
            // forge-lint: disable-next-line
            IERC20Minimal(inToken).transfer(msg.sender, inAmt);
            return;
        }

        // Outer call (ask fill callback): we received base tokens, now fill a bid order
        _isInnerCall = true;
        (bool success,) = exchange.call(
            abi.encodeWithSignature(
                "fillBidOrder(uint64,uint128,uint128,bytes,uint32)",
                bidOrderId,
                bidAmt,
                uint128(0),
                abi.encode("inner"),
                uint32(0)
            )
        );
        require(success, "Inner bid fill should succeed");
        arbitrageExecuted = true;

        // Pay quote tokens for the outer ask fill
        // Must also cover the inner bid fill's outAmt that was sent from the exchange
        // forge-lint: disable-next-line
        IERC20Minimal(inToken).transfer(msg.sender, inAmt + _innerOutAmt);
    }
}

/// @notice Callback that attempts cancel/withdraw during a flash-swap callback
/// @dev Verifies that _guardNoReentry() blocks cancel/withdraw paths when depth > 0
contract CancelDuringCallback is IGridCallback {
    address public exchange;
    uint128 public targetGridId;
    bool public cancelAttempted;
    bool public cancelSucceeded;
    bool public tryWithdraw; // false = try cancelGrid, true = try withdrawGridProfits

    constructor(address _exchange) {
        exchange = _exchange;
    }

    function setCancelTarget(uint128 _gridId) external {
        targetGridId = _gridId;
        cancelAttempted = false;
        cancelSucceeded = false;
        tryWithdraw = false;
    }

    function setWithdrawTarget(uint128 _gridId) external {
        targetGridId = _gridId;
        cancelAttempted = false;
        cancelSucceeded = false;
        tryWithdraw = true;
    }

    function gridFillCallback(address inToken, address, uint128 inAmt, uint128, bytes calldata) external override {
        cancelAttempted = true;

        bool success;
        if (tryWithdraw) {
            // Attempt withdrawGridProfits — should be blocked by _guardNoReentry()
            (success,) = exchange.call(
                abi.encodeWithSignature(
                    "withdrawGridProfits(uint48,uint256,address,uint32)",
                    targetGridId,
                    uint256(0),
                    address(this),
                    uint32(0)
                )
            );
        } else {
            // Attempt cancelGrid — should be blocked by _guardNoReentry()
            (success,) = exchange.call(
                abi.encodeWithSignature("cancelGrid(address,uint128,uint32)", address(this), targetGridId, uint32(0))
            );
        }

        cancelSucceeded = success;

        // Still pay for the outer fill so it succeeds
        // forge-lint: disable-next-line
        IERC20Minimal(inToken).transfer(msg.sender, inAmt);
    }
}

/// @notice Callback that attempts to place new grid orders during a fill — should be blocked
contract PlaceDuringCallback is IGridCallback {
    address public exchange;
    bool public placeAttempted;
    bool public placeSucceeded;

    // Place-order parameters
    address public targetBase;
    address public targetQuote;
    address public strategy;
    uint256 public askPrice0;
    uint256 public bidPrice0;
    uint256 public gap;
    uint128 public baseAmount;

    constructor(address _exchange) {
        exchange = _exchange;
    }

    function setPlaceTarget(
        address _base,
        address _quote,
        address _strategy,
        uint256 _askPrice0,
        uint256 _bidPrice0,
        uint256 _gap,
        uint128 _baseAmount
    ) external {
        targetBase = _base;
        targetQuote = _quote;
        strategy = _strategy;
        askPrice0 = _askPrice0;
        bidPrice0 = _bidPrice0;
        gap = _gap;
        baseAmount = _baseAmount;
        placeAttempted = false;
        placeSucceeded = false;
    }

    function gridFillCallback(address inToken, address, uint128 inAmt, uint128, bytes calldata) external override {
        placeAttempted = true;

        // Build a GridOrderParam and attempt placeGridOrders — should be blocked by _guardNoReentry()
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(strategy),
            bidStrategy: IGridStrategy(strategy),
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: 1,
            bidOrderCount: 1,
            baseAmount: baseAmount,
            fee: 500,
            compound: false,
            oneshot: false
        });

        // Use low-level call so failure doesn't revert the outer fill
        (bool success,) = exchange.call(
            abi.encodeWithSelector(
                TradeFacet.placeGridOrders.selector, Currency.wrap(targetBase), Currency.wrap(targetQuote), param
            )
        );

        placeSucceeded = success;

        // Still pay for the outer fill so it succeeds
        // forge-lint: disable-next-line
        IERC20Minimal(inToken).transfer(msg.sender, inAmt);
    }
}

/// @notice Callback for fillAskOrder that calls fillBidOrder internally
/// @dev Outer fillAskOrder: receives SEA (base), callback must pay USDC (quote).
///      Inner fillBidOrder: pays SEA (base), receives USDC (quote) from exchange.
///      The inner bid fill sends USDC out of the exchange, so the outer callback
///      must repay inAmt (for the outer ask) PLUS the inner bid's outAmt (USDC sent out).
///      Net effect: SEA in/out cancel, taker loses USDC on spread + fees.
contract AskCallsBidCallback is IGridCallback {
    address public exchange;
    uint256 public targetBidOrderId;
    uint128 public targetBidAmt;
    bool public innerFillExecuted;
    bool private _isInnerCall;
    uint128 private _innerOutAmt; // USDC sent out by inner fillBidOrder

    constructor(address _exchange) {
        exchange = _exchange;
    }

    function setTarget(uint256 _bidOrderId, uint128 _bidAmt) external {
        targetBidOrderId = _bidOrderId;
        targetBidAmt = _bidAmt;
        innerFillExecuted = false;
        _isInnerCall = false;
        _innerOutAmt = 0;
    }

    function gridFillCallback(address inToken, address, uint128 inAmt, uint128 outAmt, bytes calldata)
        external
        override
    {
        if (_isInnerCall) {
            // Inner call (from fillBidOrder): inToken=SEA(base), outAmt=USDC sent to us
            // Record the USDC outAmt so outer callback can compensate
            _innerOutAmt = outAmt;
            // Pay SEA to exchange for the inner bid fill
            // forge-lint: disable-next-line
            IERC20Minimal(inToken).transfer(msg.sender, inAmt);
            return;
        }

        // Outer call (from fillAskOrder): inToken=USDC(quote), we received SEA
        // Now call fillBidOrder to sell the SEA we just received for USDC
        _isInnerCall = true;
        (bool success,) = exchange.call(
            abi.encodeWithSignature(
                "fillBidOrder(uint64,uint128,uint128,bytes,uint32)",
                targetBidOrderId,
                targetBidAmt,
                uint128(0),
                abi.encode("inner-bid"),
                uint32(0)
            )
        );
        require(success, "Inner fillBidOrder should succeed");
        innerFillExecuted = true;

        // Pay USDC (quote) for the outer ask fill
        // Must also cover the USDC that the inner bid fill sent out of the exchange
        // forge-lint: disable-next-line
        IERC20Minimal(inToken).transfer(msg.sender, inAmt + _innerOutAmt);
    }
}

/// @notice Callback for fillBidOrder that calls fillAskOrder internally
/// @dev Outer fillBidOrder: receives USDC (quote), callback must pay SEA (base).
///      Inner fillAskOrder: pays USDC (quote), receives SEA (base) from exchange.
///      The inner ask fill sends SEA out of the exchange, so the outer callback
///      must repay filledAmt (for the outer bid) PLUS the inner ask's filledAmt (SEA sent out).
///      Net effect: taker loses filledAmt SEA (compensation overhead) + USDC on spread + fees.
contract BidCallsAskCallback is IGridCallback {
    address public exchange;
    uint256 public targetAskOrderId;
    uint128 public targetAskAmt;
    bool public innerFillExecuted;
    bool private _isInnerCall;
    uint128 private _innerOutAmt; // SEA sent out by inner fillAskOrder

    constructor(address _exchange) {
        exchange = _exchange;
    }

    function setTarget(uint256 _askOrderId, uint128 _askAmt) external {
        targetAskOrderId = _askOrderId;
        targetAskAmt = _askAmt;
        innerFillExecuted = false;
        _isInnerCall = false;
        _innerOutAmt = 0;
    }

    function gridFillCallback(address inToken, address, uint128 inAmt, uint128 outAmt, bytes calldata)
        external
        override
    {
        if (_isInnerCall) {
            // Inner call (from fillAskOrder): inToken=USDC(quote), outAmt=SEA sent to us
            // Record the SEA outAmt so outer callback can compensate
            _innerOutAmt = outAmt;
            // Pay USDC to exchange for the inner ask fill
            // forge-lint: disable-next-line
            IERC20Minimal(inToken).transfer(msg.sender, inAmt);
            return;
        }

        // Outer call (from fillBidOrder): inToken=SEA(base), we received USDC
        // Now call fillAskOrder to buy SEA with the USDC we just received
        _isInnerCall = true;
        (bool success,) = exchange.call(
            abi.encodeWithSignature(
                "fillAskOrder(uint64,uint128,uint128,bytes,uint32)",
                targetAskOrderId,
                targetAskAmt,
                uint128(0),
                abi.encode("inner-ask"),
                uint32(0)
            )
        );
        require(success, "Inner fillAskOrder should succeed");
        innerFillExecuted = true;

        // Pay SEA (base) for the outer bid fill
        // Must also cover the SEA that the inner ask fill sent out of the exchange
        // forge-lint: disable-next-line
        IERC20Minimal(inToken).transfer(msg.sender, inAmt + _innerOutAmt);
    }
}
