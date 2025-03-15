// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Events emitted by grid exchange
/// @notice Contains all events emitted by grid exchange
interface IOrderEvents {
    /// @notice Emitted by a pair when grid order created
    /// @param pairId pair Id
    /// @param asks How many ask orders
    /// @param bids How many ask orders
    /// @param gridId Grid Id
    /// @param askOrderId The highest price orderId of the ask grid orders
    /// @param bidOrderId The lowest price orderId of the bid grid orders
    /// @param amount The base amount of every grid order
    /// @param compound If the grid order is compound
    /// @param fee Grid order fee bips
    event GridOrderCreated(
        address indexed owner,
        uint64 pairId,
        // uint256 askPrice0,
        // uint256 askGap,
        // uint256 bidPrice0,
        // uint256 bidGap,
        uint256 amount,
        uint128 gridId,
        uint256 askOrderId,
        uint256 bidOrderId,
        uint32 asks,
        uint32 bids,
        uint32 fee,
        bool compound,
        bool oneshot
    );

    /// @notice Emitted when a whoole grid was canceled
    /// @param owner The owner of the canceled grid
    /// @param gridId The gridId to be canceled
    event CancelWholeGrid(address indexed owner, uint128 indexed gridId);

    /// @notice Emitted when a grid order was canceled
    /// @param owner The owner of the canceled order
    /// @param orderId The orderId of the order to be canceled
    /// @param gridId The gridId of the order to be canceled
    event CancelGridOrder(address indexed owner, uint128 indexed orderId, uint128 indexed gridId);

    /// @notice Emitted when a grid order was filled or partial filled
    /// @param taker The taker address
    /// @param gridOrderId The grid orderId of the order to be filled
    /// @param baseAmt The base token amount filled
    /// @param quoteVol The quote token amount filled
    /// @param orderAmt The amount in the order after filled
    /// @param orderRevAmt The reverse amount in the order after filled
    /// @param isAsk The filled maker order is Ask: true; or else false;
    event FilledOrder(
        address taker,
        uint256 gridOrderId,
        uint256 baseAmt,
        uint256 quoteVol,
        uint256 orderAmt,
        uint256 orderRevAmt,
        bool isAsk
    );

    /// @notice Emitted when the collected protocol fees are withdrawn by the factory owner
    /// @param sender The address that collects the protocol fees
    /// @param recipient The address that receives the collected protocol fees
    /// @param amount The amount of quote protocol fees that is withdrawn
    event CollectProtocol(address indexed sender, address indexed recipient, uint256 amount);

    /// @notice Emitted when the grid fee changed
    /// @param sender The address that collects the protocol fees
    /// @param gridId The grid Id
    /// @param fee The new grid fee fees
    event GridFeeChanged(address indexed sender, uint256 gridId, uint32 fee);
}
