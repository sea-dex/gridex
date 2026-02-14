// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/// @title IGridExExit
/// @author GridEx Protocol
/// @notice Interface for CancelFacet: cancel + withdraw operations
interface IGridExExit {
    /// @notice Cancel an entire grid and withdraw all remaining tokens
    function cancelGrid(address recipient, uint128 gridId, uint32 flag) external;

    /// @notice Cancel specific orders within a grid
    function cancelGridOrders(uint128 gridId, address recipient, uint256[] memory idList, uint32 flag) external;

    /// @notice Cancel a range of consecutive grid orders
    function cancelGridOrders(address recipient, uint256 startGridOrderId, uint32 howmany, uint32 flag) external;

    /// @notice Withdraw accumulated profits from a grid
    function withdrawGridProfits(uint128 gridId, uint256 amt, address to, uint32 flag) external;

    /// @notice Modify the fee for a grid
    function modifyGridFee(uint128 gridId, uint32 fee) external;
}
