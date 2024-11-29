// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Events emitted by grid exchange
/// @notice Contains all events emitted by grid exchange
interface IOrderEvents {
    /// @notice Emitted by a pair when grid order created
    /// @param asks How many ask orders
    /// @param bids How many ask orders
    /// @param gridId Grid Id
    /// @param askOrderId The highest price orderId of the ask grid orders
    /// @param bidOrderId The lowest price orderId of the bid grid orders
    /// @param askPrice0 The lowest price of sell grid orders
    /// @param askGap Price gap between sell order and it's reverse order
    /// @param bidPrice0 The highest price of buy grid orders
    /// @param bidGap Price gap between buy order and it's reverse order
    /// @param amount the base amount of every grid order
    /// @param compound if the grid order is compound
    event GridOrderCreated(
        address indexed owner,
        uint256 askPrice0,
        uint256 askGap,
        uint256 bidPrice0,
        uint256 bidGap,
        uint256 amount,
        uint32 asks,
        uint32 bids,
        uint96 gridId,
        bool compound,
        uint96 askOrderId,
        uint96 bidOrderId
    );

    /// @notice Emitted when a grid order was canceled
    /// @param owner The owner of the canceled order
    /// @param orderId The orderId of the order to be canceled
    /// @param gridId The gridId of the order to be canceled
    /// @param baseAmt sell order left amount(base token)
    /// @param quoteAmt buy order left amount(quote token)
    event CancelGridOrder(
        address indexed owner, uint96 indexed orderId, uint96 gridId, uint256 baseAmt, uint256 quoteAmt
    );

    /// @notice Emitted when a grid order was filled
    /// @param orderId The orderId of the order to be canceled
    /// @param price The grid order fill price
    /// @param baseAmt The base token amount filled
    /// @param quoteVol The quote token amount filled
    /// @param leftBaseAmt The base token amount left in the order
    /// @param leftQuoteAmt The quote token amount left in the order
    /// @param lpFee The LP trading fee
    /// @param protocolFee The protocol fee
    /// @param taker The taker address
    event FilledOrder(
        uint96 indexed orderId,
        uint256 price,
        uint256 baseAmt,
        uint256 quoteVol,
        uint256 leftBaseAmt,
        uint256 leftQuoteAmt,
        uint256 lpFee,
        uint256 protocolFee,
        address taker
    );

    /// @notice Emitted when the collected protocol fees are withdrawn by the factory owner
    /// @param sender The address that collects the protocol fees
    /// @param recipient The address that receives the collected protocol fees
    /// @param amount The amount of quote protocol fees that is withdrawn
    event CollectProtocol(address indexed sender, address indexed recipient, uint256 amount);
}
