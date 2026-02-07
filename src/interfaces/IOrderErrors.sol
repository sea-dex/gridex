// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/// @title IOrderErrors
/// @author GridEx Protocol
/// @notice Interface containing all custom errors for the GridEx protocol
/// @dev These errors provide gas-efficient error handling with descriptive messages
interface IOrderErrors {
    //////////////////////////////// Errors ////////////////////////////////

    /// @notice Thrown when a function parameter is invalid
    error InvalidParam();

    /// @notice Thrown when grid side is invalid (must be BID or ASK)
    error InvalidGridSide();

    /// @notice Thrown when grid fee is invalid or out of allowed range
    error InvalidGridFee();

    /// @notice Thrown when grid buy price0 or sell price0 is invalid
    error InvalidGridPrice();

    /// @notice Thrown when grid quote amount is invalid
    error InvalidGridAmount();

    /// @notice Thrown when grid order base amount exceeds uint96.MAX
    error ExceedMaxAmount();

    /// @notice Thrown when attempting to create a grid with zero orders
    error ZeroGridOrderCount();

    /// @notice Thrown when buy price is less than 0 or sell price overflows
    error InvalidGapPrice();

    /// @notice Thrown when there is not enough base token for the operation
    error NotEnoughBaseToken();

    /// @notice Thrown when there is not enough quote token for the operation
    error NotEnoughQuoteToken();

    /// @notice Thrown when there is not enough liquidity to fill the order
    error NotEnoughToFill();

    /// @notice Thrown when msg.sender is not the grid owner
    error NotGridOwer();

    /// @notice Thrown when the order is not a limit order
    error NotLimitOrder();

    /// @notice Thrown when msg.sender is not the order owner

    /// @notice Thrown when the strategy is not whitelisted
    error StrategyNotWhitelisted();
    error NotOrderOwner();

    /// @notice Thrown when maximum ask order ID is reached
    error ExceedMaxAskOrder();

    /// @notice Thrown when maximum bid order ID is reached
    error ExceedMaxBidOrder();

    /// @notice Thrown when calculated quote amount is zero
    error ZeroQuoteAmt();

    /// @notice Thrown when calculated quote amount exceeds uint96.max
    error ExceedQuoteAmt();

    /// @notice Thrown when calculated base amount is zero
    error ZeroBaseAmt();

    /// @notice Thrown when calculated base amount exceeds uint96.max
    error ExceedBaseAmt();

    /// @notice Thrown when grid ID is invalid
    error InvalidGridId();

    /// @notice Thrown when the grid order has already been canceled
    error OrderCanceled();

    /// @notice Thrown when attempting to withdraw profits but there are none
    error NoProfits();

    /// @notice Thrown when attempting to fill a reversed one-shot order
    error FillReversedOneShotOrder();

    /// @notice Thrown when attempting to modify fee for a oneshot grid
    error CannotModifyOneshotFee();
}
