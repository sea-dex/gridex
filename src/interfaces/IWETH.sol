// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.33;

/// @title IWETH
/// @author GridEx Protocol
/// @notice Interface for the Wrapped Ether (WETH) contract
/// @dev Standard WETH interface for wrapping and unwrapping ETH
interface IWETH {
    /// @notice Wrap ETH into WETH
    /// @dev Mints WETH to msg.sender equal to msg.value
    function deposit() external payable;

    /// @notice Transfer WETH to another address
    /// @param to The recipient address
    /// @param value The amount to transfer
    /// @return True if the transfer succeeded
    function transfer(address to, uint256 value) external returns (bool);

    /// @notice Unwrap WETH back to ETH
    /// @dev Burns WETH from msg.sender and sends ETH
    /// @param amount The amount of WETH to unwrap
    function withdraw(uint256 amount) external;
}
