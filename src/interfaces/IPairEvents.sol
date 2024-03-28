// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Events emitted by a pool
/// @notice Contains all events emitted by the pool
interface IPairEvents {
    /// @notice Emitted by a pair when grid order created
    /// @param asks How many ask orders
    /// @param bids How many ask orders
    /// @param gridId Grid Id
    /// @param askOrderId The highest price orderId of the ask grid orders
    /// @param bidOrderId The lowest price orderId of the bid grid orders
    /// @param sellPrice0 The lowest price of sell grid orders
    /// @param sellGap Price gap between sell order and it's reverse order
    /// @param buyPrice0 The highest price of buy grid orders
    /// @param buyGap Price gap between buy order and it's reverse order
    /// @param amount the base amount of every grid order
    /// @param compound if the grid order is compound
    event GridOrderCreated(
        address indexed owner,
        uint16 asks,
        uint16 bids,
        uint64 gridId,
        uint64 askOrderId,
        uint64 bidOrderId,
        uint256 sellPrice0,
        uint256 sellGap,
        uint256 buyPrice0,
        uint256 buyGap,
        uint256 amount,
        bool compound
    );

    /// @notice Emitted when a grid order was canceled
    /// @param gridId The gridId of the order to be canceled
    /// @param orderId The orderId of the order to be canceled
    /// @param baseAmt sell order left amount(base token)
    /// @param quoteAmt buy order left amount(quote token)
    event CancelGridOrder(
        uint64 gridId,
        uint64 orderId,
        uint256 baseAmt,
        uint256 quoteAmt
    );

    /// @notice Emitted when a grid order was filled
    /// @param orderId The orderId of the order to be canceled
    /// @param baseAmt The base token amount filled
    /// @param quoteVol The quote token amount filled
    /// @param leftBaseAmt The base token amount left in the order
    /// @param leftQuoteAmt The quote token amount left in the order
    /// @param totalFee Total trading fee
    /// @param lpFee The LP trading fee
    event FilledOrder(
        uint64 orderId,
        uint256 baseAmt,
        uint256 quoteVol,
        uint256 leftBaseAmt,
        uint256 leftQuoteAmt,
        uint256 totalFee,
        uint256 lpFee
    );

    /// @notice Emitted by a pair when fee protocol changed
    /// @param feeProtocolOld The gridId of the order to be canceled
    /// @param feeProtocol The orderId of the order to be canceled
    event SetFeeProtocol(uint8 feeProtocolOld, uint8 feeProtocol);

    /// @notice Emitted when the collected protocol fees are withdrawn by the factory owner
    /// @param sender The address that collects the protocol fees
    /// @param recipient The address that receives the collected protocol fees
    /// @param amount The amount of quote protocol fees that is withdrawn
    event CollectProtocol(address indexed sender, address indexed recipient, uint256 amount);
}
