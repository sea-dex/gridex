// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./IGridOrder.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../libraries/Currency.sol";

/// @title IGridExTrade
/// @author GridEx Protocol
/// @notice Interface for TradeFacet: place + fill grid orders
interface IGridExTrade {
    /// @notice Place grid orders with ETH as either base or quote token
    // forge-lint: disable-next-line(mixed-case-function)
    function placeETHGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param)
        external
        payable;

    /// @notice Place grid orders with ERC20 tokens
    function placeGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param) external;

    /// @notice Fill a single ask grid order (buy base token)
    function fillAskOrder(uint256 gridOrderId, uint128 amt, uint128 minAmt, bytes calldata data, uint32 flag)
        external
        payable;

    /// @notice Fill multiple ask orders in a single transaction
    function fillAskOrders(
        uint64 pairId,
        uint256[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt,
        uint128 minAmt,
        bytes calldata data,
        uint32 flag
    ) external payable;

    /// @notice Fill a single bid grid order (sell base token)
    function fillBidOrder(uint256 gridOrderId, uint128 amt, uint128 minAmt, bytes calldata data, uint32 flag)
        external
        payable;

    /// @notice Fill multiple bid orders in a single transaction
    function fillBidOrders(
        uint64 pairId,
        uint256[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt,
        uint128 minAmt,
        bytes calldata data,
        uint32 flag
    ) external payable;
}
