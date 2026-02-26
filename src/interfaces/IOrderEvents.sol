// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

/// @title IOrderEvents
/// @author GridEx Protocol
/// @notice Interface containing all events emitted by the GridEx protocol
/// @dev These events are used for off-chain tracking and indexing of protocol activity
interface IOrderEvents {
    /// @notice Emitted when a new grid order is created
    /// @param owner The address that created the grid order
    /// @param pairId The trading pair ID
    /// @param amount The base amount of every grid order
    /// @param gridId The unique grid identifier
    /// @param asks The number of ask orders in the grid
    /// @param bids The number of bid orders in the grid
    /// @param fee The grid order fee in basis points
    /// @param compound Whether the grid order compounds profits
    /// @param oneshot Whether the grid order is one-shot (non-reversible)
    event GridOrderCreated(
        address indexed owner,
        uint64 pairId,
        // uint256 askPrice0,
        // uint256 askGap,
        // uint256 bidPrice0,
        // uint256 bidGap,
        uint256 amount,
        uint128 gridId,
        // uint256 askOrderId,
        // uint256 bidOrderId,
        uint32 asks,
        uint32 bids,
        uint32 fee,
        bool compound,
        bool oneshot
    );

    /// @notice Emitted when an entire grid is canceled
    /// @param owner The owner of the canceled grid
    /// @param gridId The ID of the canceled grid
    event CancelWholeGrid(address indexed owner, uint128 indexed gridId);

    /// @notice Emitted when a single grid order is canceled
    /// @param owner The owner of the canceled order
    /// @param orderId The ID of the canceled order
    /// @param gridId The grid ID containing the canceled order
    event CancelGridOrder(address indexed owner, uint128 indexed orderId, uint128 indexed gridId);

    /// @notice Emitted when a grid order is filled or partially filled
    /// @param taker The address that filled the order
    /// @param gridOrderId The combined grid and order ID
    /// @param baseAmt The base token amount filled
    /// @param quoteVol The quote token volume filled
    /// @param orderAmt The remaining amount in the order after fill
    /// @param orderRevAmt The reverse amount in the order after fill
    /// @param isAsk True if the filled order was an ask order, false for bid
    event FilledOrder(
        address taker,
        uint256 gridOrderId,
        uint256 baseAmt,
        uint256 quoteVol,
        uint256 orderAmt,
        uint256 orderRevAmt,
        bool isAsk
    );

    /// @notice Emitted when protocol fees are collected and withdrawn
    /// @param sender The address that initiated the collection
    /// @param recipient The address that receives the collected fees
    /// @param amount The amount of fees collected
    event CollectProtocol(address indexed sender, address indexed recipient, uint256 amount);

    /// @notice Emitted when a grid's fee is changed
    /// @param sender The address that changed the fee
    /// @param gridId The grid ID whose fee was changed
    /// @param fee The new fee in basis points
    event GridFeeChanged(address indexed sender, uint256 gridId, uint32 fee);

    /// @notice Emitted when the oneshot protocol fee is changed
    /// @param sender The address that changed the fee
    /// @param oldFeeBps The old fee in basis points
    /// @param newFeeBps The new fee in basis points
    event OneshotProtocolFeeChanged(address indexed sender, uint32 oldFeeBps, uint32 newFeeBps);

    /// @notice Emitted when a strategy's whitelist status is changed
    /// @param sender The address that changed the whitelist status
    /// @param strategy The strategy contract address
    /// @param whitelisted True if the strategy is now whitelisted, false if removed
    event StrategyWhitelistUpdated(address indexed sender, address indexed strategy, bool whitelisted);
}
