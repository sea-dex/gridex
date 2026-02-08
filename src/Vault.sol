// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/// @title Vault
/// @author GridEx Protocol
/// @notice A simple vault contract for holding protocol fees and assets
/// @dev Only the owner can withdraw assets from the vault
contract Vault is Owned {
    using SafeTransferLib for ERC20;

    /// @notice Creates a new Vault with the specified owner
    /// @param _owner The address that will own this vault
    constructor(address _owner) Owned(_owner) {}

    /// @notice Withdraw ERC20 tokens from the vault
    /// @dev Only callable by the owner
    /// @param token The ERC20 token address to withdraw
    /// @param to The recipient address
    /// @param amount The amount to withdraw
    function withdrawERC20(address token, address to, uint256 amount) external onlyOwner {
        ERC20(token).safeTransfer(to, amount);
    }

    /// @notice Withdraw ETH from the vault
    /// @dev Only callable by the owner. Reverts if the transfer fails.
    /// @param to The recipient address
    /// @param amount The amount of ETH to withdraw
    // forge-lint: disable-next-line(mixed-case-function)
    function withdrawETH(address to, uint256 amount) external onlyOwner {
        (bool success,) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /// @notice Allows the vault to receive ETH
    receive() external payable {}
}
