// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Events emitted by a pool
/// @notice Contains all events emitted by the pool
interface IPairEvents {
    /// @notice Emitted by a pair when grid order created
    /// @param asks How many ask orders
    /// @param bids How many ask orders
    /// @param gridId Grid Id
    /// @param orderId The last orderId of the grid
    /// @param sellPrice0 The lowest price of sell grid orders
    /// @param sellGap Price gap between sell order and it's reverse order
    /// @param buyPrice0 The highest price of buy grid orders
    /// @param buyGap Price gap between buy order and it's reverse order
    /// @param amount the base amount of every grid order
    event GridOrderCreated(
        address indexed owner,
        uint16 asks,
        uint16 bids,
        uint64 gridId,
        uint64 orderId,
        uint256 sellPrice0,
        uint256 sellGap,
        uint256 buyPrice0,
        uint256 buyGap,
        uint256 amount
    );

    /// @notice Emitted when a grid order was canceled
    /// @param gridId The gridId of the order to be canceled
    /// @param orderId The orderId of the order to be canceled
    /// @param baseAmt sell order left amount(base token)
    /// @param quoteAmt buy order left amount(quote token)
    event CancelGridOrder(
        uint64 gridId,
        uint64 orderId,
        uint96 baseAmt,
        uint96 quoteAmt
    );

    /// @notice Emitted when a grid order was filled
    /// @param orderId The orderId of the order to be canceled
    /// @param amount if the order is sell order, amount is the base token amount; or else quote token amount
    /// @param totalFee total trading fee
    /// @param lpFee the LP trading fee
    event FilledOrder(
        uint64 orderId,
        uint96 amount,
        uint96 totalFee,
        uint96 lpFee
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
