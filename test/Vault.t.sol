// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";

/// @title VaultTest
/// @notice Tests for Vault withdrawal functions (withdrawERC20, withdrawETH)
contract VaultTest is Test {
    Vault public vault;
    SEA public sea;
    USDC public usdc;

    address public owner;
    address public recipient = address(0x1234);
    address public nonOwner = address(0x5678);

    uint256 public constant INITIAL_ETH = 10 ether;
    uint256 public constant INITIAL_SEA = 1000 ether;
    uint256 public constant INITIAL_USDC = 10000_000_000; // 10000 USDC (6 decimals)

    function setUp() public {
        owner = address(this);
        vault = new Vault(owner);
        sea = new SEA();
        usdc = new USDC();

        // Fund the vault with tokens and ETH
        // forge-lint: disable-next-line
        sea.transfer(address(vault), INITIAL_SEA);
        // forge-lint: disable-next-line
        usdc.transfer(address(vault), INITIAL_USDC);
        vm.deal(address(vault), INITIAL_ETH);
    }

    // ============ withdrawERC20 Tests ============

    /// @notice Test successful ERC20 withdrawal by owner
    function test_withdrawERC20_success() public {
        uint256 withdrawAmount = 100 ether;
        uint256 recipientBalanceBefore = sea.balanceOf(recipient);
        uint256 vaultBalanceBefore = sea.balanceOf(address(vault));

        vault.withdrawERC20(address(sea), recipient, withdrawAmount);

        assertEq(sea.balanceOf(recipient), recipientBalanceBefore + withdrawAmount);
        assertEq(sea.balanceOf(address(vault)), vaultBalanceBefore - withdrawAmount);
    }

    /// @notice Test withdrawing full ERC20 balance
    function test_withdrawERC20_fullBalance() public {
        uint256 vaultBalance = sea.balanceOf(address(vault));

        vault.withdrawERC20(address(sea), recipient, vaultBalance);

        assertEq(sea.balanceOf(recipient), vaultBalance);
        assertEq(sea.balanceOf(address(vault)), 0);
    }

    /// @notice Test withdrawing zero amount (should succeed)
    function test_withdrawERC20_zeroAmount() public {
        uint256 recipientBalanceBefore = sea.balanceOf(recipient);

        vault.withdrawERC20(address(sea), recipient, 0);

        assertEq(sea.balanceOf(recipient), recipientBalanceBefore);
    }

    /// @notice Test withdrawing USDC (6 decimals token)
    function test_withdrawERC20_differentDecimals() public {
        uint256 withdrawAmount = 1000_000_000; // 1000 USDC
        uint256 recipientBalanceBefore = usdc.balanceOf(recipient);

        vault.withdrawERC20(address(usdc), recipient, withdrawAmount);

        assertEq(usdc.balanceOf(recipient), recipientBalanceBefore + withdrawAmount);
    }

    /// @notice Test that non-owner cannot withdraw ERC20
    function test_withdrawERC20_revertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        vault.withdrawERC20(address(sea), recipient, 100 ether);
    }

    /// @notice Test withdrawing more than balance reverts
    function test_withdrawERC20_revertInsufficientBalance() public {
        uint256 vaultBalance = sea.balanceOf(address(vault));

        vm.expectRevert();
        vault.withdrawERC20(address(sea), recipient, vaultBalance + 1);
    }

    /// @notice Test withdrawing to zero address (depends on token implementation)
    function test_withdrawERC20_toZeroAddress() public {
        // This may or may not revert depending on the token implementation
        // Our test tokens don't have zero address checks
        vault.withdrawERC20(address(sea), address(0), 100 ether);
        assertEq(sea.balanceOf(address(0)), 100 ether);
    }

    /// @notice Fuzz test for ERC20 withdrawal amounts
    function testFuzz_withdrawERC20(uint256 amount) public {
        uint256 vaultBalance = sea.balanceOf(address(vault));
        amount = bound(amount, 0, vaultBalance);

        uint256 recipientBalanceBefore = sea.balanceOf(recipient);

        vault.withdrawERC20(address(sea), recipient, amount);

        assertEq(sea.balanceOf(recipient), recipientBalanceBefore + amount);
    }

    // ============ withdrawETH Tests ============

    /// @notice Test successful ETH withdrawal by owner
    function test_withdrawETH_success() public {
        uint256 withdrawAmount = 1 ether;
        uint256 recipientBalanceBefore = recipient.balance;
        uint256 vaultBalanceBefore = address(vault).balance;

        vault.withdrawETH(recipient, withdrawAmount);

        assertEq(recipient.balance, recipientBalanceBefore + withdrawAmount);
        assertEq(address(vault).balance, vaultBalanceBefore - withdrawAmount);
    }

    /// @notice Test withdrawing full ETH balance
    function test_withdrawETH_fullBalance() public {
        uint256 vaultBalance = address(vault).balance;

        vault.withdrawETH(recipient, vaultBalance);

        assertEq(recipient.balance, vaultBalance);
        assertEq(address(vault).balance, 0);
    }

    /// @notice Test withdrawing zero ETH (should succeed)
    function test_withdrawETH_zeroAmount() public {
        uint256 recipientBalanceBefore = recipient.balance;

        vault.withdrawETH(recipient, 0);

        assertEq(recipient.balance, recipientBalanceBefore);
    }

    /// @notice Test that non-owner cannot withdraw ETH
    function test_withdrawETH_revertNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        vault.withdrawETH(recipient, 1 ether);
    }

    /// @notice Test withdrawing more ETH than balance reverts
    function test_withdrawETH_revertInsufficientBalance() public {
        uint256 vaultBalance = address(vault).balance;

        vm.expectRevert("ETH transfer failed");
        vault.withdrawETH(recipient, vaultBalance + 1);
    }

    /// @notice Test ETH withdrawal to contract that rejects ETH
    function test_withdrawETH_revertReceiverRejects() public {
        // Deploy a contract that rejects ETH
        RejectingReceiver rejecter = new RejectingReceiver();

        vm.expectRevert("ETH transfer failed");
        vault.withdrawETH(address(rejecter), 1 ether);
    }

    /// @notice Test ETH withdrawal to contract with expensive receive
    function test_withdrawETH_expensiveReceiver() public {
        // Deploy a contract with expensive receive function
        ExpensiveReceiver expensive = new ExpensiveReceiver();

        // Should still succeed as we forward all gas
        vault.withdrawETH(address(expensive), 1 ether);
        assertEq(address(expensive).balance, 1 ether);
    }

    /// @notice Fuzz test for ETH withdrawal amounts
    function testFuzz_withdrawETH(uint256 amount) public {
        uint256 vaultBalance = address(vault).balance;
        amount = bound(amount, 0, vaultBalance);

        uint256 recipientBalanceBefore = recipient.balance;

        vault.withdrawETH(recipient, amount);

        assertEq(recipient.balance, recipientBalanceBefore + amount);
    }

    // ============ Receive ETH Tests ============

    /// @notice Test vault can receive ETH
    function test_receiveETH() public {
        uint256 vaultBalanceBefore = address(vault).balance;
        uint256 sendAmount = 5 ether;

        (bool success,) = address(vault).call{value: sendAmount}("");

        assertTrue(success);
        assertEq(address(vault).balance, vaultBalanceBefore + sendAmount);
    }

    /// @notice Test vault can receive ETH from multiple sources
    function test_receiveETH_multipleSources() public {
        address sender1 = address(0xAAA);
        address sender2 = address(0xBBB);
        vm.deal(sender1, 10 ether);
        vm.deal(sender2, 10 ether);

        uint256 vaultBalanceBefore = address(vault).balance;

        vm.prank(sender1);
        (bool success1,) = address(vault).call{value: 3 ether}("");

        vm.prank(sender2);
        (bool success2,) = address(vault).call{value: 2 ether}("");

        assertTrue(success1);
        assertTrue(success2);
        assertEq(address(vault).balance, vaultBalanceBefore + 5 ether);
    }

    // ============ Ownership Tests ============

    /// @notice Test ownership transfer and withdrawal
    function test_ownershipTransfer() public {
        address newOwner = address(0x9999);

        // Transfer ownership
        vault.transferOwnership(newOwner);

        // Old owner can no longer withdraw
        vm.expectRevert("UNAUTHORIZED");
        vault.withdrawERC20(address(sea), recipient, 100 ether);

        // New owner can withdraw
        vm.prank(newOwner);
        vault.withdrawERC20(address(sea), recipient, 100 ether);
        assertEq(sea.balanceOf(recipient), 100 ether);
    }
}

/// @notice Contract that rejects ETH transfers
contract RejectingReceiver {
    receive() external payable {
        revert("No ETH accepted");
    }
}

/// @notice Contract with expensive receive function
contract ExpensiveReceiver {
    uint256 public counter;

    receive() external payable {
        // Do some expensive operations
        for (uint256 i = 0; i < 100; i++) {
            counter += 1;
        }
    }
}
