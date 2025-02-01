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
    /// @param askPrice0 The lowest price of sell grid orders
    /// @param askGap Price gap between sell order and it's reverse order
    /// @param bidPrice0 The highest price of buy grid orders
    /// @param bidGap Price gap between buy order and it's reverse order
    /// @param amount The base amount of every grid order
    /// @param compound If the grid order is compound
    /// @param fee Grid order fee bips
    event GridOrderCreated(
        address indexed owner,
        uint64 pairId,
        uint256 askPrice0,
        uint256 askGap,
        uint256 bidPrice0,
        uint256 bidGap,
        uint256 amount,
        uint128 gridId,
        uint128 askOrderId,
        uint128 bidOrderId,
        uint32 asks,
        uint32 bids,
        uint32 fee,
        bool compound
    );

    /// @notice Emitted when a whoole grid was canceled
    /// @param owner The owner of the canceled grid
    /// @param gridId The gridId to be canceled
    event CancelWholeGrid(address indexed owner, uint128 indexed gridId);

    /// @notice Emitted when a grid order was canceled
    /// @param owner The owner of the canceled order
    /// @param orderId The orderId of the order to be canceled
    /// @param gridId The gridId of the order to be canceled
    event CancelGridOrder(
        address indexed owner,
        uint128 indexed orderId,
        uint128 indexed gridId
    );

    /// @notice Emitted when a grid order was filled or partial filled
    /// @param gridId The gridId of the order to be filled
    /// @param orderId The orderId of the order to be filled
    /// @param price The grid order fill price
    /// @param baseAmt The base token amount filled
    /// @param quoteVol The quote token amount filled
    /// @param orderBaseAmt The base token amount in the order after filled
    /// @param orderQuoteAmt The quote token amount in the order after filled
    /// @param isAsk The filled maker order is Ask: true; or else false;
    /// @param taker The taker address
    event FilledOrder(
        uint128 indexed gridId,
        uint128 indexed orderId,
        uint256 price,
        uint256 baseAmt,
        uint256 quoteVol,
        uint256 orderBaseAmt,
        uint256 orderQuoteAmt,
        bool isAsk,
        address taker
    );

    /// @notice Emitted when the collected protocol fees are withdrawn by the factory owner
    /// @param sender The address that collects the protocol fees
    /// @param recipient The address that receives the collected protocol fees
    /// @param amount The amount of quote protocol fees that is withdrawn
    event CollectProtocol(
        address indexed sender,
        address indexed recipient,
        uint256 amount
    );
}
