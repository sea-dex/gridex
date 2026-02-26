// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "../interfaces/IGridOrder.sol";
import {IPair} from "../interfaces/IPair.sol";

import {Currency} from "../libraries/Currency.sol";
import {GridOrder} from "../libraries/GridOrder.sol";
import {GridExStorage} from "../libraries/GridExStorage.sol";

/// @title ViewFacet
/// @author GridEx Protocol
/// @notice Read-only query functions for the GridEx protocol
/// @dev Delegatecalled by GridExRouter. All functions are view/pure.
contract ViewFacet {
    using GridOrder for GridOrder.GridState;

    // ─── Grid order queries ──────────────────────────────────────────

    /// @notice Get information about a single grid order
    /// @param id The grid order ID (64 bits)
    /// @return The order information struct
    function getGridOrder(uint64 id) external view returns (IGridOrder.OrderInfo memory) {
        return GridExStorage.layout().gridState.getOrderInfo(id, false);
    }

    /// @notice Get information about multiple grid orders
    /// @param idList Array of grid order IDs to query (64 bits each)
    /// @return orderList Array of order information structs
    function getGridOrders(uint64[] calldata idList) external view returns (IGridOrder.OrderInfo[] memory) {
        GridExStorage.Layout storage l = GridExStorage.layout();
        uint256 len = idList.length;
        IGridOrder.OrderInfo[] memory orderList = new IGridOrder.OrderInfo[](len);

        for (uint256 i; i < len;) {
            orderList[i] = l.gridState.getOrderInfo(idList[i], false);
            unchecked {
                ++i;
            }
        }
        return orderList;
    }

    /// @notice Get the accumulated profits for a grid
    /// @param gridId The grid ID to query (48 bits)
    /// @return The profit amount in quote tokens
    function getGridProfits(uint48 gridId) external view returns (uint256) {
        return GridExStorage.layout().gridState.gridConfigs[gridId].profits;
    }

    /// @notice Get the configuration for a grid
    /// @param gridId The grid ID to query (48 bits)
    /// @return The grid configuration struct
    function getGridConfig(uint48 gridId) external view returns (IGridOrder.GridConfig memory) {
        return GridExStorage.layout().gridState.gridConfigs[gridId];
    }

    // ─── Protocol config queries ─────────────────────────────────────

    /// @notice Get the current protocol fee for oneshot orders
    /// @return The oneshot protocol fee in basis points
    function getOneshotProtocolFeeBps() external view returns (uint32) {
        return GridExStorage.layout().gridState.getOneshotProtocolFeeBps();
    }

    /// @notice Check if a strategy is whitelisted
    /// @param strategy The strategy contract address to check
    /// @return True if the strategy is whitelisted
    function isStrategyWhitelisted(address strategy) external view returns (bool) {
        return GridExStorage.layout().whitelistedStrategies[strategy];
    }

    // ─── Pair queries ────────────────────────────────────────────────

    /// @notice Get the base and quote tokens for a pair
    /// @param pairId The pair ID to query
    /// @return base The base token address
    /// @return quote The quote token address
    function getPairTokens(uint64 pairId) external view returns (Currency base, Currency quote) {
        GridExStorage.Layout storage l = GridExStorage.layout();
        IPair.Pair memory pair = l.getPairById[pairId];
        if (pair.pairId == 0) {
            revert IPair.InvalidPairId();
        }
        return (pair.base, pair.quote);
    }

    /// @notice Get the pair ID for a given base and quote token combination
    /// @param base The base token address
    /// @param quote The quote token address
    /// @return The pair ID (0 if not exists)
    function getPairIdByTokens(Currency base, Currency quote) external view returns (uint64) {
        return GridExStorage.layout().getPair[base][quote].pairId;
    }

    /// @notice Get pair info by pair ID
    /// @param pairId The pair ID
    /// @return base The base token
    /// @return quote The quote token
    /// @return id The pair ID
    function getPairById(uint64 pairId) external view returns (Currency base, Currency quote, uint64 id) {
        IPair.Pair memory pair = GridExStorage.layout().getPairById[pairId];
        return (pair.base, pair.quote, pair.pairId);
    }

    /// @notice Check if the contract is paused
    /// @return True if paused
    function paused() external view returns (bool) {
        return GridExStorage.layout().paused;
    }

    // ─── Ownership / Router queries ──────────────────────────────────

    /// @notice Get the contract owner
    /// @return The owner address
    function owner() external view returns (address) {
        return GridExStorage.layout().owner;
    }

    /// @notice Get the vault address
    /// @return The vault address
    function vault() external view returns (address) {
        return GridExStorage.layout().vault;
    }

    /// @notice Get the WETH address
    /// @return The WETH address
    // forge-lint: disable-next-line
    function WETH() external view returns (address) {
        return GridExStorage.layout().weth;
    }

    /// @notice Get the facet address for a given selector
    /// @param selector The function selector to look up
    /// @return The facet address mapped to the selector
    function facetAddress(bytes4 selector) external view returns (address) {
        return GridExStorage.layout().selectorToFacet[selector];
    }
}
