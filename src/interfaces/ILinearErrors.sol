// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

/// @title ILinearErrors
/// @author GridEx Protocol
/// @notice Custom errors for Linear strategy parameter validation.
interface ILinearErrors {
    /// @notice Thrown when `count` is zero.
    error LinearInvalidCount();

    /// @notice Thrown when `price0` is zero/out of range or `gap` is zero.
    error LinearInvalidPriceOrGap();

    /// @notice Thrown when ask-side `gap` is non-positive.
    error LinearAskGapNonPositive();

    /// @notice Thrown when ask-side `gap` is greater than or equal to `price0`.
    error LinearAskGapTooLarge();

    /// @notice Thrown when ask-side `price0 + (count-1)*gap` would overflow `uint256`.
    error LinearAskPriceOverflow();

    /// @notice Thrown when computed ask-side quote amount rounds up to zero.
    error LinearAskZeroQuote();

    /// @notice Thrown when bid-side `gap` is non-negative.
    error LinearBidGapNonNegative();

    /// @notice Thrown when bid-side `price0 + (-gap)` would overflow `uint256`.
    error LinearBidPriceOverflow();

    /// @notice Thrown when computed bid-side last price is non-positive.
    error LinearBidInvalidLastPrice();

    /// @notice Thrown when computed bid-side quote amount rounds up to zero.
    error LinearBidZeroQuote();
}
