// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.33;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../libraries/Currency.sol";

/// @title IGridStrategy
/// @author GridEx Protocol
/// @notice Interface for grid pricing strategies
/// @dev Implement this interface to create custom pricing strategies for grid orders
interface IGridStrategy {
    /// @notice Validate grid strategy parameters before grid creation
    /// @dev Should revert if parameters are invalid
    /// @param isAsk True if validating ask grid parameters, false for bid
    /// @param amt The base amount per order
    /// @param data Encoded strategy parameters
    /// @param count The number of orders in the grid
    function validateParams(bool isAsk, uint128 amt, bytes calldata data, uint32 count) external pure;

    /// @notice Initialize strategy state for a new grid
    /// @dev Called when a grid is created to store strategy parameters
    /// @param isAsk True if creating ask strategy, false for bid
    /// @param gridId The unique grid identifier
    /// @param data Encoded strategy parameters
    function createGridStrategy(bool isAsk, uint128 gridId, bytes memory data) external;

    /// @notice Get the price for a specific order in the grid
    /// @dev Price is in quote tokens per base token (scaled by 1e18 or similar)
    /// @param isAsk True if querying ask order price, false for bid
    /// @param gridId The grid identifier
    /// @param idx The order index within the grid (0-based)
    /// @return The order price
    function getPrice(bool isAsk, uint128 gridId, uint128 idx) external view returns (uint256);

    /// @notice Get the reverse price for a filled order
    /// @dev Used when an order is filled and needs to be placed on the opposite side
    /// @param isAsk True if querying ask order reverse price, false for bid
    /// @param gridId The grid identifier
    /// @param idx The order index within the grid (0-based)
    /// @return The reverse price
    function getReversePrice(bool isAsk, uint128 gridId, uint128 idx) external view returns (uint256);
}
