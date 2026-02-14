// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./IGridOrder.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../libraries/Currency.sol";

/// @title IGridExRouter
/// @author GridEx Protocol
/// @notice Interface for the GridExRouter: combined interface for all operations
interface IGridExRouter {
    /// @notice Emitted when a facet selector mapping is updated
    event FacetUpdated(bytes4 indexed selector, address indexed facet);

    /// @notice Emitted when a quote token's priority is set or updated
    event QuotableTokenUpdated(Currency quote, uint256 priority);

    /// @notice Emitted when grid profits are withdrawn
    event WithdrawProfit(uint128 gridId, Currency quote, address to, uint256 amt);

    /// @notice Get the facet address for a selector
    function facetAddress(bytes4 selector) external view returns (address);

    /// @notice Get the contract owner
    function owner() external view returns (address);
}
