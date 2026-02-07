// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./IGridStrategy.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../libraries/Currency.sol";

/// @title IGridOrder
/// @author GridEx Protocol
/// @notice Interface defining grid order data structures
/// @dev Contains all structs used for grid order management
interface IGridOrder {
    /// @notice Parameters for creating a new grid order
    /// @dev Used when calling placeGridOrders or placeETHGridOrders
    struct GridOrderParam {
        /// @notice The strategy contract for ask orders
        IGridStrategy askStrategy;
        /// @notice The strategy contract for bid orders
        IGridStrategy bidStrategy;
        /// @notice Encoded parameters for the ask strategy
        bytes askData;
        /// @notice Encoded parameters for the bid strategy
        bytes bidData;
        // uint256 askPrice0;
        // uint256 askGap;
        // uint256 bidPrice0;
        // uint256 bidGap;
        /// @notice Number of ask orders to create
        uint32 askOrderCount;
        /// @notice Number of bid orders to create
        uint32 bidOrderCount;
        /// @notice Fee in basis points (1 bps = 0.01%)
        uint32 fee;
        /// @notice Whether to compound profits back into orders
        bool compound;
        /// @notice Whether orders are one-shot (non-reversible)
        bool oneshot;
        /// @notice Base token amount per order
        uint128 baseAmount;
    }

    /// @notice Configuration for a grid
    /// @dev Stored on-chain for each created grid
    struct GridConfig {
        /// @notice The grid owner address
        address owner;
        /// @notice The strategy contract for ask orders
        IGridStrategy askStrategy;
        /// @notice The strategy contract for bid orders
        IGridStrategy bidStrategy;
        /// @notice Accumulated profits in quote token
        uint128 profits;
        /// @notice Base token amount per order
        uint128 baseAmt;
        /// @notice Starting order ID for ask orders
        uint128 startAskOrderId;
        /// @notice Starting order ID for bid orders
        uint128 startBidOrderId;
        /// @notice The unique grid identifier
        uint128 gridId;
        /// @notice The trading pair ID
        uint64 pairId;
        /// @notice Number of ask orders
        uint32 askOrderCount;
        /// @notice Number of bid orders
        uint32 bidOrderCount;
        /// @notice Fee in basis points
        uint32 fee;
        /// @notice Whether profits are compounded
        bool compound;
        /// @notice Whether orders are one-shot
        bool oneshot;
        /// @notice Grid status: 0 = invalid, 1 = normal, 2 = canceled
        uint32 status;
    }

    /// @notice Individual grid order data
    /// @dev Minimal storage for gas efficiency
    struct Order {
        /// @notice For ask orders: base amount; For bid orders: quote amount
        uint128 amount;
        /// @notice Reverse amount (filled from the other side)
        uint128 revAmount;
    }

    /// @notice Extended order information for queries
    /// @dev Returned by getGridOrder and getGridOrders
    struct OrderInfo {
        /// @notice True if this is an ask order
        bool isAsk;
        /// @notice Whether profits are compounded
        bool compound;
        /// @notice Whether the order is one-shot
        bool oneshot;
        /// @notice Fee in basis points
        uint32 fee;
        /// @notice Order status: 0 = normal, 1 = cancelled
        uint32 status;
        /// @notice The grid ID this order belongs to
        uint128 gridId;
        /// @notice The order ID within the grid
        uint128 orderId;
        /// @notice Current order amount
        uint128 amount;
        /// @notice Current reverse amount
        uint128 revAmount;
        /// @notice Base token amount per order
        uint128 baseAmt;
        /// @notice The order price
        uint256 price;
        /// @notice The reverse price (for filled orders)
        uint256 revPrice;
        /// @notice The trading pair ID
        uint64 pairId;
    }

    /// @notice Result of filling an order
    /// @dev Returned by internal fill functions
    struct OrderFillResult {
        /// @notice Base amount filled
        uint128 filledAmt;
        /// @notice Quote volume filled
        uint128 filledVol;
        /// @notice Protocol fee charged
        uint128 protocolFee;
        /// @notice LP fee charged
        uint128 lpFee;
        /// @notice Profit generated
        uint128 profit;
        /// @notice Remaining order amount after fill
        uint128 orderAmt;
        /// @notice Remaining reverse amount after fill
        uint128 orderRevAmt;
        /// @notice The trading pair ID
        uint64 pairId;
    }
}
