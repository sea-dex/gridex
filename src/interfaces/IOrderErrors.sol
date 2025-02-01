// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IOrderErrors {
    //////////////////////////////// Errors ////////////////////////////////

    /// @notice Thrown when param invalid
    error InvalidParam();

    /// @notice Thrown when grid side invalid, either BID(1) or ASK(2)
    error InvalidGridSide();

    /// @notice Thrown when grid fee invalid
    error InvalidGridFee();

    /// @notice Thrown when grid buy price0 or sell price0 invalid
    error InvalidGridPrice();

    /// @notice Thrown when grid quote amount invalid
    error InvalidGridAmount();

    /// @notice Thrown when grid order base amount great than uint96.MAX
    error ExceedMaxAmount();

    /// @notice Thrown when no grid order
    error ZeroGridOrderCount();

    /// @notice Thrown when buy price less than 0 or sell prive overflow
    error InvalidGapPrice();

    /// @notice Thrown when base token not enough
    error NotEnoughBaseToken();

    /// @notice Thrown when quote token not enough
    error NotEnoughQuoteToken();

    /// @notice Thrown when not enough to be filled
    error NotEnoughToFill();

    /// @notice Thrown when msg.sender is NOT grid owner
    error NotGridOwer();

    /// @notice Thrown when order is NOT limit order
    error NotLimitOrder();

    /// @notice Thrown when msg.sender is NOT order owner
    error NotOrderOwner();

    /// @notice Thrown when max ask orderId reached
    error ExceedMaxAskOrder();

    /// @notice Thrown when max bid orderId reached
    error ExceedMaxBidOrder();

    /// @notice Thrown when calculate quote amount is 0
    error ZeroQuoteAmt();

    /// @notice Thrown when calculate quote amount exceed uint96.max
    error ExceedQuoteAmt();

    /// @notice Thrown when calculate base amount is 0
    error ZeroBaseAmt();

    /// @notice Thrown when calculate base amount exceed uint96.max
    error ExceedBaseAmt();

    /// @notice Thrown when gridId invalid
    error InvalidGridId();

    /// @notice Thrown when grid order has been canceled
    error OrderCanceled();

    /// @notice Thrown when no profit on withdraw grid profits
    error NoProfits();
}
