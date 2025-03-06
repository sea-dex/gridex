// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "../libraries/Currency.sol";

interface IGridStrategy {
    /// @notice Validate grid strategy parameters
    /// @param isAsk The data and count is ask grid or not
    /// @param data The grid strategy parameter data
    /// @param count The grid order count
    function validateParams(bool isAsk, uint128 amt, bytes calldata data, uint32 count) external pure;

    /// @notice Create grid strategy
    /// @param gridId The grid order Id
    /// @param data The grid strategy parameter data
    function createGridStrategy(bool isAsk, uint128 gridId, bytes memory data) external;

    /// @notice Get grid order price
    /// @param gridId Thee grid order Id
    /// @param idx The index of the order in the grid, from 0
    function getPrice(bool isAsk, uint128 gridId, uint128 idx) external view returns (uint256);

    /// @notice Get grid order reverse price
    /// @param gridId Thee grid order Id
    /// @param idx The index of the order in the grid, from 0
    function getReversePrice(bool isAsk, uint128 gridId, uint128 idx) external view returns (uint256);
}
