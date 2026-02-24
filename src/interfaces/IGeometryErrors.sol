// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

/// @title IGeometryErrors
/// @author GridEx Protocol
/// @notice Custom errors for Geometry strategy parameter validation.
interface IGeometryErrors {
    /// @notice Thrown when `count` is zero.
    error GeometryInvalidCount();

    /// @notice Thrown when `price0` or `ratio` is invalid.
    error GeometryInvalidPriceOrRatio();

    /// @notice Thrown when ask-side ratio is not greater than 1.
    error GeometryAskRatioTooLow();

    /// @notice Thrown when ask-side reverse quote would round to zero.
    error GeometryAskZeroQuote();

    /// @notice Thrown when bid-side ratio is not less than 1.
    error GeometryBidRatioTooHigh();

    /// @notice Thrown when bid-side quote would round to zero.
    error GeometryBidZeroQuote();
}
