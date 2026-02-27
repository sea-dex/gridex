// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.33;

/// @title IProtocolErrors
/// @author GridEx Protocol
/// @notice Additional custom errors used across protocol modules.
interface IProtocolErrors {
    /// @notice Thrown when a taker callback did not transfer in required funds.
    error CallbackInsufficientInput();

    /// @notice Thrown when a provided pairId mismatches the order fill result.
    error PairIdMismatch();

    /// @notice Thrown when a token ordering tie-breaker check fails.
    error TokenOrderInvalid();

    /// @notice Thrown when a zero address is provided where a valid address is required.
    error InvalidAddress();

    /// @notice Thrown when the contract has already been initialized.
    error AlreadyInitialized();

    /// @notice Thrown when insufficient ETH is sent for an operation.
    error InsufficientETH();

    /// @notice Thrown when an ETH transfer fails.
    error ETHTransferFailed();
}
