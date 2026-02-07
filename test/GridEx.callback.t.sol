// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {GridExBaseTest} from "./GridExBase.t.sol";
import {IGridCallback} from "../src/interfaces/IGridCallback.sol";
import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {IERC20Minimal} from "../src/interfaces/IERC20Minimal.sol";

/// @title GridExCallbackTest
/// @notice Tests for callback pattern with various receiver behaviors
contract GridExCallbackTest is GridExBaseTest {
    MaliciousCallback public maliciousCallback;
    ReentrantCallback public reentrantCallback;
    InsufficientPayCallback public insufficientCallback;
    ValidCallback public validCallback;
    
    function setUp() public override {
        super.setUp();
        
        maliciousCallback = new MaliciousCallback();
        reentrantCallback = new ReentrantCallback(address(exchange));
        insufficientCallback = new InsufficientPayCallback();
        validCallback = new ValidCallback();
        
        // Fund the callback contracts
        sea.transfer(address(maliciousCallback), 1000 ether);
        usdc.transfer(address(maliciousCallback), 1000_000_000);
        
        sea.transfer(address(reentrantCallback), 1000 ether);
        usdc.transfer(address(reentrantCallback), 1000_000_000);
        
        sea.transfer(address(insufficientCallback), 1000 ether);
        usdc.transfer(address(insufficientCallback), 1000_000_000);
        
        sea.transfer(address(validCallback), 1000 ether);
        usdc.transfer(address(validCallback), 1000_000_000);
        
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
    }

    // ============ Valid Callback Tests ============

    /// @notice Test valid callback for fillAskOrder
    function test_callback_validFillAsk() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        
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
        uint128 bidOrderId = 0x0000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, bidOrderId);
        
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
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        
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
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        
        // Insufficient callback pays nothing
        insufficientCallback.setPayPercentage(0);
        
        vm.prank(address(insufficientCallback));
        vm.expectRevert();
        exchange.fillAskOrder(gridOrderId, amt, 0, abi.encode("callback"), 0);
    }

    /// @notice Test reentrancy protection on fillAskOrder
    /// @dev The callback attempts reentrancy, which fails internally.
    ///      The outer call succeeds because the callback handles the failure gracefully.
    ///      This test verifies that reentrancy was attempted and blocked.
    function test_callback_reentrantFillAsk() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        
        // Set up reentrant callback to try fillAskOrder again
        reentrantCallback.setReentryTarget(gridOrderId, amt, true);
        
        // The outer call succeeds because the callback catches the reentrancy failure
        // and still pays the required amount
        vm.prank(address(reentrantCallback));
        exchange.fillAskOrder(gridOrderId, amt, 0, abi.encode("reenter"), 0);
        
        // Verify that reentrancy was attempted (hasReentered flag is set)
        assertTrue(reentrantCallback.hasReentered(), "Reentrancy should have been attempted");
    }

    /// @notice Test reentrancy protection on fillBidOrder
    /// @dev The callback attempts reentrancy, which fails internally.
    ///      The outer call succeeds because the callback handles the failure gracefully.
    ///      This test verifies that reentrancy was attempted and blocked.
    function test_callback_reentrantFillBid() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 bidOrderId = 0x0000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, bidOrderId);
        
        // Set up reentrant callback to try fillBidOrder again
        reentrantCallback.setReentryTarget(gridOrderId, amt, false);
        
        // The outer call succeeds because the callback catches the reentrancy failure
        // and still pays the required amount
        vm.prank(address(reentrantCallback));
        exchange.fillBidOrder(gridOrderId, amt, 0, abi.encode("reenter"), 0);
        
        // Verify that reentrancy was attempted (hasReentered flag is set)
        assertTrue(reentrantCallback.hasReentered(), "Reentrancy should have been attempted");
    }
    
    /// @notice Test that reentrancy actually fails (callback doesn't pay if reentrancy succeeds)
    /// @dev Uses a callback that only pays if reentrancy fails
    function test_callback_reentrantFillAsk_failsWithoutPayment() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        
        // Use a callback that doesn't pay if reentrancy fails
        ReentrantNoPayCallback noPayCallback = new ReentrantNoPayCallback(address(exchange));
        sea.transfer(address(noPayCallback), 1000 ether);
        usdc.transfer(address(noPayCallback), 1000_000_000);
        
        vm.startPrank(address(noPayCallback));
        sea.approve(address(exchange), type(uint256).max);
        usdc.approve(address(exchange), type(uint256).max);
        vm.stopPrank();
        
        noPayCallback.setReentryTarget(gridOrderId, amt, true);
        
        // This should revert because the callback doesn't pay after reentrancy fails
        vm.prank(address(noPayCallback));
        vm.expectRevert();
        exchange.fillAskOrder(gridOrderId, amt, 0, abi.encode("reenter"), 0);
    }

    /// @notice Test callback that reverts
    function test_callback_reverts() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        
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
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256 gridOrderId = toGridOrderId(1, orderId);
        
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
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256[] memory idList = new uint256[](3);
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
        uint128 bidOrderId = 0x0000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256[] memory idList = new uint256[](3);
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

    /// @notice Test insufficient payment in multi-order callback
    function test_callback_fillAskOrders_insufficientPayment() public {
        uint256 askPrice0 = PRICE_MULTIPLIER / 500 / (10 ** 12);
        uint256 gap = askPrice0 / 20;
        uint256 bidPrice0 = askPrice0 - gap;
        uint128 amt = 1 ether;
        uint128 orderId = 0x80000000000000000000000000000001;

        _placeOrders(address(sea), address(usdc), amt, 5, 5, askPrice0, bidPrice0, gap, false, 500);

        uint256[] memory idList = new uint256[](3);
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
}

/// @notice Malicious callback that can revert on demand
contract MaliciousCallback is IGridCallback {
    bool public shouldRevert;
    
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
    
    function gridFillCallback(
        address inToken,
        address,
        uint128 inAmt,
        uint128,
        bytes calldata
    ) external override {
        if (shouldRevert) {
            revert("Malicious revert");
        }
        // Pay the required amount
        IERC20Minimal(inToken).transfer(msg.sender, inAmt);
    }
}

/// @notice Callback that attempts reentrancy
contract ReentrantCallback is IGridCallback {
    address public exchange;
    uint256 public targetOrderId;
    uint128 public targetAmt;
    bool public isAsk;
    bool public hasReentered;
    
    constructor(address _exchange) {
        exchange = _exchange;
    }
    
    function setReentryTarget(uint256 _orderId, uint128 _amt, bool _isAsk) external {
        targetOrderId = _orderId;
        targetAmt = _amt;
        isAsk = _isAsk;
        hasReentered = false;
    }
    
    function gridFillCallback(
        address inToken,
        address,
        uint128 inAmt,
        uint128,
        bytes calldata
    ) external override {
        if (!hasReentered) {
            hasReentered = true;
            // Attempt reentrancy
            if (isAsk) {
                // This should fail due to reentrancy guard
                (bool success,) = exchange.call(
                    abi.encodeWithSignature(
                        "fillAskOrder(uint256,uint128,uint128,bytes,uint32)",
                        targetOrderId,
                        targetAmt,
                        uint128(0),
                        "",
                        uint32(0)
                    )
                );
                require(!success, "Reentrancy should fail");
            } else {
                (bool success,) = exchange.call(
                    abi.encodeWithSignature(
                        "fillBidOrder(uint256,uint128,uint128,bytes,uint32)",
                        targetOrderId,
                        targetAmt,
                        uint128(0),
                        "",
                        uint32(0)
                    )
                );
                require(!success, "Reentrancy should fail");
            }
        }
        // Pay the required amount
        IERC20Minimal(inToken).transfer(msg.sender, inAmt);
    }
}

/// @notice Callback that pays less than required
contract InsufficientPayCallback is IGridCallback {
    uint256 public payPercentage = 100;
    
    function setPayPercentage(uint256 _percentage) external {
        payPercentage = _percentage;
    }
    
    function gridFillCallback(
        address inToken,
        address,
        uint128 inAmt,
        uint128,
        bytes calldata
    ) external override {
        // Pay only a percentage of required amount
        uint128 payAmt = uint128((uint256(inAmt) * payPercentage) / 100);
        if (payAmt > 0) {
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
    
    function gridFillCallback(
        address inToken,
        address,
        uint128 inAmt,
        uint128,
        bytes calldata
    ) external override {
        // Pay the full required amount
        IERC20Minimal(inToken).transfer(msg.sender, inAmt);
    }
}

/// @notice Callback that attempts reentrancy and doesn't pay if it fails
/// @dev This is used to verify that reentrancy protection actually blocks the call
contract ReentrantNoPayCallback is IGridCallback {
    address public exchange;
    uint256 public targetOrderId;
    uint128 public targetAmt;
    bool public isAsk;
    bool public reentrancySucceeded;
    
    constructor(address _exchange) {
        exchange = _exchange;
    }
    
    function setReentryTarget(uint256 _orderId, uint128 _amt, bool _isAsk) external {
        targetOrderId = _orderId;
        targetAmt = _amt;
        isAsk = _isAsk;
        reentrancySucceeded = false;
    }
    
    function gridFillCallback(
        address inToken,
        address,
        uint128 inAmt,
        uint128,
        bytes calldata
    ) external override {
        // Attempt reentrancy
        bool success;
        if (isAsk) {
            (success,) = exchange.call(
                abi.encodeWithSignature(
                    "fillAskOrder(uint256,uint128,uint128,bytes,uint32)",
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
                    "fillBidOrder(uint256,uint128,uint128,bytes,uint32)",
                    targetOrderId,
                    targetAmt,
                    uint128(0),
                    "",
                    uint32(0)
                )
            );
        }
        
        // Only pay if reentrancy succeeded (which it shouldn't)
        if (success) {
            reentrancySucceeded = true;
            IERC20Minimal(inToken).transfer(msg.sender, inAmt);
        }
        // If reentrancy failed, don't pay - this will cause the outer call to fail
    }
}
