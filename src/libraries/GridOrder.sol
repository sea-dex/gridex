// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "../interfaces/IGridOrder.sol";
import {IGridStrategy} from "../interfaces/IGridStrategy.sol";
import {IOrderErrors} from "../interfaces/IOrderErrors.sol";
import {IOrderEvents} from "../interfaces/IOrderEvents.sol";

import {FullMath} from "./FullMath.sol";
import {Lens} from "./Lens.sol";
import {ProtocolConstants} from "./ProtocolConstants.sol";

/// @title GridOrder
/// @author GridEx Protocol
/// @notice Library for managing grid order state and operations
/// @dev Contains all logic for placing, filling, and canceling grid orders.
///      Grid orders are automated trading strategies that place multiple orders at different price levels.
///      This library handles:
///      - Grid order placement with configurable ask/bid strategies
///      - Order filling with fee calculation (LP fees and protocol fees)
///      - Grid and order cancellation with proper refund calculations
///      - Compound and oneshot order modes
library GridOrder {
    /// @notice Minimum fee in basis points (0.0001%)
    /// @dev Fee is represented as basis points where 1 = 0.0001% (1e-6)
    ///      MIN_FEE of 10 = 0.0001%
    uint32 public constant MIN_FEE = 1;

    /// @notice Maximum fee in basis points (10%)
    /// @dev MAX_FEE of 100000 = 10%
    uint32 public constant MAX_FEE = 100000;

    /// @dev Mask for extracting order ID from grid order ID (lower 16 bits)
    uint64 private constant ORDER_ID_MASK = 0xFFFF;

    /// @dev Mask for identifying ask orders (high bit of uint16 order ID is set)
    uint16 private constant ASK_ORDER_MASK = ProtocolConstants.ASK_ORDER_FLAG;

    /// @dev Grid status: normal/active - grid is operational and orders can be filled
    uint32 private constant GRID_STATUS_NORMAL = 0;

    /// @dev Grid status: canceled - grid is no longer active, orders cannot be filled
    uint32 private constant GRID_STATUS_CANCELED = 1;

    /// @notice State structure for managing all grid orders
    /// @dev Stored in contract storage. This is the main state container for the grid order system.
    ///      Grid order IDs are composed of: (gridId << 16) | orderId
    ///      - gridId: Unique identifier for a grid (48 bits)
    ///      - orderId: Unique identifier for an order within the grid (16 bits)
    ///      Order ID ranges:
    ///      - Bid orders: 0-32767 (0x0000-0x7FFF)
    ///      - Ask orders: 32768-65535 (0x8000-0xFFFF)
    struct GridState {
        /// @notice Next grid ID to assign (starts from 1)
        /// @dev Incremented each time a new grid is created
        uint64 nextGridId;
        /// @notice Protocol fee in basis points for oneshot orders (all fee goes to protocol, no LP fee)
        /// @dev Default is 500 (0.05%). For oneshot orders, there is no LP fee component.
        uint32 oneshotProtocolFeeBps;
        /// @notice Mapping from grid order ID to order status
        /// @dev false = GRID_STATUS_NORMAL (active), true = GRID_STATUS_CANCELED
        mapping(uint64 gridOrderId => bool) orderStatus;
        /// @notice Mapping from grid order ID to order data
        /// @dev Contains the current amount and reverse amount for each order
        mapping(uint64 gridOrderId => IGridOrder.Order) orderInfos;
        /// @notice Mapping from grid ID to grid configuration
        /// @dev Contains all configuration parameters for a grid including owner, strategies, and fees
        mapping(uint48 gridId => IGridOrder.GridConfig) gridConfigs;
    }

    /// @notice Initialize the grid state
    /// @dev Sets initial values for grid ID counter
    /// @param self The grid state storage to initialize
    function initialize(GridState storage self) internal {
        self.nextGridId = uint64(ProtocolConstants.GRID_ID_START);
        self.oneshotProtocolFeeBps = 500; // default oneshot fee bps 0.05%
    }

    /// @notice Validate grid order parameters
    /// @dev Checks fee range and validates strategy parameters. For oneshot orders, fee validation is skipped
    ///      as the fee will be overridden with oneshotProtocolFeeBps
    /// @param param The grid order parameters to validate
    function validateGridOrderParam(IGridOrder.GridOrderParam calldata param) private pure {
        // Require at least one order (ask or bid)
        if (param.askOrderCount == 0 && param.bidOrderCount == 0) {
            revert IOrderErrors.ZeroGridOrderCount();
        }

        // For oneshot orders, skip user fee validation since it will be overridden
        if (!param.oneshot) {
            if (param.fee > MAX_FEE || param.fee < MIN_FEE) {
                revert IOrderErrors.InvalidGridFee();
            }
        }
        // else {
        // For oneshot, validate that oneshotFeeBps is set
        // if (oneshotFeeBps > MAX_FEE || oneshotFeeBps < MIN_FEE) {
        //     revert IOrderErrors.InvalidGridFee();
        // }
        // }

        unchecked {
            uint256 totalBaseAmt = uint256(param.baseAmount) * uint256(param.askOrderCount);
            if (totalBaseAmt > type(uint128).max) {
                revert IOrderErrors.ExceedMaxAmount();
            }

            // buy price should great than 0
            if (param.bidOrderCount > 0) {
                // require(param.bidOrderCount > 1, "E1");
                param.bidStrategy.validateParams(false, param.baseAmount, param.bidData, param.bidOrderCount);
            }

            if (param.askOrderCount > 0) {
                // ASK orders
                param.askStrategy.validateParams(true, param.baseAmount, param.askData, param.askOrderCount);
            }
        }
    }

    /// @notice Combine grid ID and order ID into a single grid order ID
    /// @param gridId The grid ID (48 bits)
    /// @param orderId The order ID within the grid (16 bits)
    /// @return id The combined grid order ID (64 bits)
    function toGridOrderId(uint48 gridId, uint16 orderId) public pure returns (uint64 id) {
        id = (uint64(gridId) << 16) | uint64(orderId);
    }

    /// @notice Check if an order ID represents an ask order
    /// @param orderId The order ID to check (16 bits)
    /// @return True if the order is an ask order (high bit set)
    function isAskGridOrder(uint16 orderId) public pure returns (bool) {
        return (orderId & ASK_ORDER_MASK) != 0;
    }

    /// @notice Extract grid ID and order ID from a combined grid order ID
    /// @param gridOrderId The combined grid order ID (64 bits)
    /// @return The grid ID (48 bits)
    /// @return The order ID (16 bits)
    function extractGridIdOrderId(uint64 gridOrderId) internal pure returns (uint48, uint16) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return (uint48(gridOrderId >> 16), uint16(gridOrderId & ORDER_ID_MASK));
    }

    /// @notice Get order index from order ID
    /// @dev For bid orders (0-32767), index equals orderId
    ///      For ask orders (32768-65535), index = orderId - 32768
    /// @param orderId The order ID (16 bits)
    /// @return The order index within the grid
    function getOrderIndex(uint16 orderId) internal pure returns (uint16) {
        if (orderId & ASK_ORDER_MASK != 0) {
            // Ask order: subtract ASK_ORDER_START_ID (0x8000 = 32768)
            return orderId - ProtocolConstants.ASK_ORDER_START_ID;
        } else {
            // Bid order: index equals orderId
            return orderId;
        }
    }

    /// @notice Get order amounts for cancellation
    /// @dev Returns base and quote amounts to refund when canceling an order
    /// @param self The grid state storage
    /// @param gridConf The grid configuration
    /// @param orderId The order ID to cancel (16 bits)
    /// @return baseAmt The base token amount to refund
    /// @return quoteAmt The quote token amount to refund
    function getOrderAmountsForCancel(GridState storage self, IGridOrder.GridConfig memory gridConf, uint16 orderId)
        internal
        view
        returns (uint128 baseAmt, uint128 quoteAmt)
    {
        bool isAsk = isAskGridOrder(orderId);
        uint16 orderIdx = getOrderIndex(orderId);

        if (isAsk) {
            if (orderIdx >= gridConf.askOrderCount) {
                revert IOrderErrors.InvalidGridId();
            }
        } else {
            if (orderIdx >= gridConf.bidOrderCount) {
                revert IOrderErrors.InvalidGridId();
            }
        }

        IGridOrder.Order memory order = self.orderInfos[toGridOrderId(gridConf.gridId, orderId)];

        if (order.amount == 0 && order.revAmount == 0) {
            // not initialized
            if (isAsk) {
                return (gridConf.baseAmt, 0);
            } else {
                uint256 price = gridConf.bidStrategy.getPrice(false, gridConf.gridId, orderIdx);
                uint128 quoteVol = Lens.calcQuoteAmount(gridConf.baseAmt, price, false);
                return (0, quoteVol);
            }
        } else {
            if (isAsk) {
                return (order.amount, order.revAmount);
            } else {
                return (order.revAmount, order.amount);
            }
        }
    }

    /// @notice Create a new grid configuration
    /// @param self The grid state storage
    /// @param pairId The trading pair ID
    /// @param maker The grid owner address
    /// @param param The grid order parameters
    /// @return The new grid ID (48 bits)
    function createGridConfig(
        GridState storage self,
        uint64 pairId,
        address maker,
        IGridOrder.GridOrderParam calldata param
    ) internal returns (uint48) {
        uint48 gridId = uint48(self.nextGridId++);

        // For oneshot orders, override user fee with oneshotProtocolFeeBps
        uint32 effectiveFee = param.oneshot ? self.oneshotProtocolFeeBps : param.fee;

        self.gridConfigs[gridId] = IGridOrder.GridConfig({
            owner: maker,
            profits: 0,
            gridId: gridId,
            pairId: pairId,
            baseAmt: param.baseAmount,
            askStrategy: param.askStrategy,
            bidStrategy: param.bidStrategy,
            askOrderCount: param.askOrderCount,
            bidOrderCount: param.bidOrderCount,
            fee: effectiveFee,
            compound: param.compound,
            oneshot: param.oneshot,
            status: GRID_STATUS_NORMAL
        });

        return gridId;
    }

    /// @notice Place a new grid order
    /// @dev Creates grid config and calculates required token amounts
    ///      Order IDs: bid orders use 0-32767, ask orders use 32768-65535
    /// @param self The grid state storage
    /// @param pairId The trading pair ID
    /// @param maker The grid owner address
    /// @param param The grid order parameters
    /// @return The grid ID (48 bits)
    /// @return The total base token amount required
    /// @return The total quote token amount required
    function placeGridOrder(
        GridState storage self,
        uint64 pairId,
        address maker,
        IGridOrder.GridOrderParam calldata param
    ) internal returns (uint48, uint128, uint128) {
        validateGridOrderParam(param);

        uint48 gridId = createGridConfig(self, pairId, maker, param);

        uint128 baseAmt = param.baseAmount;
        uint128 quoteAmt;

        // Ask orders start at ASK_ORDER_START_ID (0x8000 = 32768)
        // Bid orders start at BID_ORDER_START_ID (0)

        if (param.askOrderCount > 0) {
            IGridStrategy(param.askStrategy).createGridStrategy(true, gridId, param.askData);
        }

        if (param.bidOrderCount > 0) {
            IGridStrategy(param.bidStrategy).createGridStrategy(false, gridId, param.bidData);

            for (uint16 i; i < param.bidOrderCount;) {
                uint256 price = IGridStrategy(param.bidStrategy).getPrice(false, gridId, i);
                uint128 amt = Lens.calcQuoteAmount(baseAmt, price, false);
                quoteAmt += amt;
                unchecked {
                    ++i;
                }
            }
        }

        return (
            gridId,
            // toGridOrderId(gridId, ProtocolConstants.ASK_ORDER_START_ID),
            // toGridOrderId(gridId, ProtocolConstants.BID_ORDER_START_ID),
            baseAmt * param.askOrderCount,
            quoteAmt
        );
    }

    /// @notice Get order information
    /// @dev Retrieves full order info including prices and amounts
    /// @param self The grid state storage
    /// @param gridOrderId The combined grid order ID
    /// @param forFill Whether this is for filling (reverts if canceled)
    /// @return orderInfo The order information struct
    function getOrderInfo(GridState storage self, uint64 gridOrderId, bool forFill)
        internal
        view
        returns (IGridOrder.OrderInfo memory orderInfo)
    {
        (uint48 gridId, uint16 orderId) = extractGridIdOrderId(gridOrderId);
        bool isAsk = isAskGridOrder(orderId);
        IGridOrder.Order memory order = self.orderInfos[gridOrderId];
        IGridOrder.GridConfig memory gridConf = self.gridConfigs[gridId];

        // Cache order index calculation - used multiple times
        uint16 orderIdx = getOrderIndex(orderId);

        if (isAsk) {
            if (orderIdx >= gridConf.askOrderCount) {
                revert IOrderErrors.InvalidGridId();
            }
        } else {
            if (orderIdx >= gridConf.bidOrderCount) {
                revert IOrderErrors.InvalidGridId();
            }
        }

        if (self.orderStatus[gridOrderId] || gridConf.status != GRID_STATUS_NORMAL) {
            if (forFill) {
                revert IOrderErrors.OrderCanceled();
            }
            orderInfo.status = GRID_STATUS_CANCELED;
        } else {
            orderInfo.status = GRID_STATUS_NORMAL;
        }

        orderInfo.gridId = gridId;
        orderInfo.orderId = orderId;

        // order prices
        uint256 price;
        // order amounts
        uint128 baseAmt = gridConf.baseAmt;
        orderInfo.baseAmt = baseAmt;
        if (order.amount == 0 && order.revAmount == 0) {
            // has not been initialized yet
            if (isAsk) {
                orderInfo.amount = baseAmt;
            } else {
                price = gridConf.bidStrategy.getPrice(false, gridId, orderIdx);
                orderInfo.amount = Lens.calcQuoteAmount(baseAmt, price, false);
            }
        } else {
            orderInfo.amount = order.amount;
            orderInfo.revAmount = order.revAmount;
        }

        if (isAsk) {
            IGridStrategy askStrategy = gridConf.askStrategy;
            price = askStrategy.getPrice(true, gridId, orderIdx);
            orderInfo.price = price;
            orderInfo.revPrice = askStrategy.getReversePrice(true, gridId, orderIdx);
        } else {
            IGridStrategy bidStrategy = gridConf.bidStrategy;
            if (price == 0) {
                price = bidStrategy.getPrice(false, gridId, orderIdx);
            }
            orderInfo.price = price;
            orderInfo.revPrice = bidStrategy.getReversePrice(false, gridId, orderIdx);
        }

        orderInfo.isAsk = isAsk;
        orderInfo.compound = gridConf.compound;
        orderInfo.oneshot = gridConf.oneshot;
        orderInfo.fee = gridConf.fee;
        orderInfo.pairId = gridConf.pairId;

        return orderInfo;
    }

    /// @notice Mark a one-shot order as completed
    /// @param self The grid state storage
    /// @param gridOrderId The grid order ID to complete
    function completeOneShotOrder(GridState storage self, uint64 gridOrderId) internal {
        self.orderStatus[gridOrderId] = true;
    }

    /// @notice Fill an ask order (taker buys base token)
    /// @dev Calculates fill amounts, fees, and updates order state
    /// @param self The grid state storage
    /// @param gridOrderId The grid order ID to fill
    /// @param amt The base token amount to fill
    /// @return result The fill result containing amounts and fees
    function fillAskOrder(
        GridState storage self,
        uint64 gridOrderId,
        uint128 amt // base token amt
    )
        internal
        returns (IGridOrder.OrderFillResult memory result)
    {
        uint128 orderBaseAmt; // base token amount of the grid order
        uint128 orderQuoteAmt; // quote token amount of the grid order
        uint256 sellPrice;

        IGridOrder.OrderInfo memory orderInfo = getOrderInfo(self, gridOrderId, true);
        if (orderInfo.isAsk) {
            orderBaseAmt = orderInfo.amount;
            orderQuoteAmt = orderInfo.revAmount;
            sellPrice = orderInfo.price;
        } else {
            if (orderInfo.oneshot) {
                revert IOrderErrors.FillReversedOneShotOrder();
            }
            orderBaseAmt = orderInfo.revAmount;
            orderQuoteAmt = orderInfo.amount;
            sellPrice = orderInfo.revPrice;
        }

        if (amt > orderBaseAmt) {
            amt = orderBaseAmt;
        }
        if (amt == 0) {
            revert IOrderErrors.ZeroBaseAmt();
        }
        // quote volume taker will pay: quoteVol = filled * price
        uint128 quoteVol = Lens.calcQuoteAmount(amt, sellPrice, true);

        // For oneshot orders, 75% protocol fee, 25% maker fee
        if (orderInfo.oneshot) {
            (result.lpFee, result.protocolFee) = Lens.calculateOneshotFee(quoteVol, orderInfo.fee);
        } else {
            (result.lpFee, result.protocolFee) = Lens.calculateFees(quoteVol, orderInfo.fee);
        }
        unchecked {
            // Safe: amt less than orderBaseAmt
            orderBaseAmt -= amt;
        }
        // calculate orderQuoteAmt and grid profit
        {
            if (orderInfo.compound) {
                orderQuoteAmt += quoteVol + result.lpFee; // all quote reverse
            } else {
                // reverse order only buy base amt
                // uint128 base = orderInfo.baseAmt;
                uint256 buyPrice = orderInfo.isAsk ? orderInfo.revPrice : orderInfo.price;
                uint128 quota = Lens.calcQuoteAmount(orderInfo.baseAmt, buyPrice, false);
                // increase profit if sell quote amount > baseAmt * price
                unchecked {
                    if (orderQuoteAmt >= quota) {
                        result.profit = quoteVol + result.lpFee;
                    } else {
                        uint128 rev = orderQuoteAmt + quoteVol + result.lpFee;
                        if (rev > quota) {
                            orderQuoteAmt = quota;
                            result.profit = rev - quota;
                        } else {
                            orderQuoteAmt += quoteVol + result.lpFee;
                        }
                    }
                }
            }
        }

        // update storage order
        if (orderInfo.isAsk) {
            result.orderAmt = orderBaseAmt;
            result.orderRevAmt = orderQuoteAmt;
            if (orderInfo.oneshot && orderBaseAmt == 0) {
                completeOneShotOrder(self, gridOrderId);
            }
        } else {
            result.orderAmt = orderQuoteAmt;
            result.orderRevAmt = orderBaseAmt;
        }

        result.filledAmt = amt;
        result.filledVol = quoteVol;
        result.pairId = orderInfo.pairId;

        IGridOrder.Order storage order = self.orderInfos[gridOrderId];
        order.amount = result.orderAmt;
        order.revAmount = result.orderRevAmt;

        if (result.profit > 0) {
            self.gridConfigs[orderInfo.gridId].profits += uint128(result.profit);
        }

        return result;
    }

    /// @notice Fill a bid order (taker sells base token)
    /// @dev Calculates fill amounts, fees, and updates order state
    /// @param self The grid state storage
    /// @param gridOrderId The grid order ID to fill (64 bits)
    /// @param amt The base token amount to fill
    /// @return result The fill result containing amounts and fees
    function fillBidOrder(
        GridState storage self,
        uint64 gridOrderId,
        uint128 amt // base token amt
    )
        internal
        returns (IGridOrder.OrderFillResult memory result)
    {
        uint128 orderBaseAmt; // base token amount of the grid order
        uint128 orderQuoteAmt; // quote token amount of the grid order
        uint256 buyPrice;

        IGridOrder.OrderInfo memory orderInfo = getOrderInfo(self, gridOrderId, true);
        if (orderInfo.isAsk) {
            if (orderInfo.oneshot) {
                revert IOrderErrors.FillReversedOneShotOrder();
            }
            orderBaseAmt = orderInfo.amount;
            orderQuoteAmt = orderInfo.revAmount;
            // orderPrice = gridConfig.startAskPrice + (orderId - gridConfig.startAskOrderId) * gridConfig.askGap;
            buyPrice = orderInfo.revPrice; // - gridConfig.askGap; // order.revPrice;
        } else {
            orderBaseAmt = orderInfo.revAmount;
            orderQuoteAmt = orderInfo.amount;
            // orderPrice = gridConfig.startBidPrice + (orderId - gridConfig.startBidOrderId) * gridConfig.bidGap;
            buyPrice = orderInfo.price;
        }

        // quote volume maker pays (use FullMath directly to avoid revert on zero)
        uint256 rawQuote = FullMath.mulDiv(uint256(amt), buyPrice, Lens.PRICE_MULTIPLIER);
        if (rawQuote == 0) {
            // Dust amount too small to produce any quote — return zero-filled result so caller can skip
            result.pairId = orderInfo.pairId;
            return result;
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 filledVol = uint128(rawQuote); // safe: amt is uint128, price < 2^128, so rawQuote < 2^128
        if (filledVol > orderQuoteAmt) {
            amt = uint128(Lens.calcBaseAmount(orderQuoteAmt, buyPrice, true));
            filledVol = orderQuoteAmt;
        }

        if (amt == 0) {
            revert IOrderErrors.ZeroBaseAmt();
        }

        // For oneshot orders, 75% protocol fee, 25% maker fee
        if (orderInfo.oneshot) {
            (result.lpFee, result.protocolFee) = Lens.calculateOneshotFee(filledVol, orderInfo.fee);
        } else {
            (result.lpFee, result.protocolFee) = Lens.calculateFees(filledVol, orderInfo.fee);
        }

        orderBaseAmt += amt;

        if (orderInfo.compound) {
            orderQuoteAmt -= filledVol - result.lpFee; // all quote reverse
        } else {
            // lpFee into profit (for oneshot, lpFee is 25% of fee going to maker as profit)
            result.profit = uint128(result.lpFee);
            orderQuoteAmt -= filledVol;
        }

        // update result
        result.filledAmt = amt;
        result.filledVol = filledVol;
        result.pairId = orderInfo.pairId;

        if (orderInfo.isAsk) {
            result.orderAmt = orderBaseAmt;
            result.orderRevAmt = orderQuoteAmt;
        } else {
            result.orderAmt = orderQuoteAmt;
            result.orderRevAmt = orderBaseAmt;
            if (orderInfo.oneshot && orderQuoteAmt == 0) {
                completeOneShotOrder(self, gridOrderId);
            }
        }

        IGridOrder.Order storage order = self.orderInfos[gridOrderId];
        order.amount = result.orderAmt;
        order.revAmount = result.orderRevAmt;

        if (result.profit > 0) {
            // uint128 gridId = orderInfo.gridId;
            // IGridOrder.GridConfig storage gridConfig = gridConfigs[gridId];
            self.gridConfigs[orderInfo.gridId].profits += uint128(result.profit);
        }
        return result;
    }

    /// @notice Cancel an entire grid
    /// @dev Cancels all orders in the grid and returns token amounts to refund
    /// @param self The grid state storage
    /// @param sender The address requesting cancellation (must be owner)
    /// @param gridId The grid ID to cancel (48 bits)
    /// @return The pair ID
    /// @return The total base token amount to refund
    /// @return The total quote token amount to refund
    function cancelGrid(GridState storage self, address sender, uint48 gridId)
        internal
        returns (uint64, uint256, uint256)
    {
        IGridOrder.GridConfig memory gridConf = self.gridConfigs[gridId];
        if (sender != gridConf.owner) {
            revert IOrderErrors.NotGridOwner();
        }

        if (gridConf.status != GRID_STATUS_NORMAL) {
            revert IOrderErrors.OrderCanceled();
        }

        uint256 baseAmt;
        uint256 quoteAmt;

        // Cancel ask orders (orderIds: 0x8000 to 0x8000 + askOrderCount - 1)
        if (gridConf.askOrderCount > 0) {
            uint16 askCount = gridConf.askOrderCount;
            for (uint16 i; i < askCount;) {
                uint16 orderId = ProtocolConstants.ASK_ORDER_START_ID + i;
                uint64 gridOrderId = toGridOrderId(gridId, orderId);
                if (self.orderStatus[gridOrderId]) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                (uint128 ba, uint128 qa) = getOrderAmountsForCancel(self, gridConf, orderId);
                unchecked {
                    baseAmt += ba;
                    quoteAmt += qa;
                    ++i;
                }
            }
        }

        // Cancel bid orders (orderIds: 0 to bidOrderCount - 1)
        if (gridConf.bidOrderCount > 0) {
            uint16 bidCount = gridConf.bidOrderCount;
            for (uint16 i; i < bidCount;) {
                uint16 orderId = i; // Bid orders start at 0
                uint64 gridOrderId = toGridOrderId(gridId, orderId);
                if (self.orderStatus[gridOrderId]) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                (uint128 ba, uint128 qa) = getOrderAmountsForCancel(self, gridConf, orderId);
                unchecked {
                    baseAmt += ba;
                    quoteAmt += qa;
                    ++i;
                }
            }
        }

        // clean grid profits
        if (gridConf.profits > 0) {
            quoteAmt += gridConf.profits;
            self.gridConfigs[gridId].profits = 0;
        }

        self.gridConfigs[gridId].status = GRID_STATUS_CANCELED;

        return (gridConf.pairId, baseAmt, quoteAmt);
    }

    /// @notice Cancel specific orders within a grid
    /// @dev Cancels only the specified orders and returns token amounts to refund
    /// @param self The grid state storage
    /// @param sender The address requesting cancellation (must be owner)
    /// @param gridId The grid ID containing the orders (48 bits)
    /// @param idList Array of grid order IDs to cancel (64 bits each)
    /// @return The pair ID
    /// @return The total base token amount to refund
    /// @return The total quote token amount to refund
    function cancelGridOrders(GridState storage self, address sender, uint48 gridId, uint64[] memory idList)
        internal
        returns (uint64, uint256, uint256)
    {
        IGridOrder.GridConfig memory gridConf = self.gridConfigs[gridId];
        if (sender != gridConf.owner) {
            revert IOrderErrors.NotGridOwner();
        }

        if (gridConf.status != GRID_STATUS_NORMAL) {
            revert IOrderErrors.OrderCanceled();
        }

        uint256 baseAmt;
        uint256 quoteAmt;
        uint256 len = idList.length;
        for (uint256 i; i < len;) {
            uint64 gridOrderId = idList[i];
            (uint48 gid, uint16 orderId) = extractGridIdOrderId(gridOrderId);
            if (gid != gridId) {
                revert IOrderErrors.InvalidGridId();
            }

            // Validate orderId is within valid range
            bool isAsk = isAskGridOrder(orderId);
            uint16 orderIdx = getOrderIndex(orderId);
            if (isAsk) {
                if (orderIdx >= gridConf.askOrderCount) {
                    revert IOrderErrors.InvalidGridId();
                }
            } else {
                if (orderIdx >= gridConf.bidOrderCount) {
                    revert IOrderErrors.InvalidGridId();
                }
            }

            if (self.orderStatus[gridOrderId]) {
                revert IOrderErrors.OrderCanceled();
            }

            (uint128 ba, uint128 qa) = getOrderAmountsForCancel(self, gridConf, orderId);
            unchecked {
                baseAmt += ba;
                quoteAmt += qa;
            }
            self.orderStatus[gridOrderId] = true;
            emit IOrderEvents.CancelGridOrder(msg.sender, orderId, gridId);
            unchecked {
                ++i;
            }
        }

        return (gridConf.pairId, baseAmt, quoteAmt);
    }

    /// @notice Modify the fee for a grid
    /// @dev Only the grid owner can modify the fee. Oneshot grids cannot have their fee modified.
    /// @param self The grid state storage
    /// @param sender The address requesting the modification (must be owner)
    /// @param gridId The grid ID to modify (48 bits)
    /// @param fee The new fee in basis points
    function modifyGridFee(GridState storage self, address sender, uint48 gridId, uint32 fee) internal {
        IGridOrder.GridConfig storage gridConf = self.gridConfigs[gridId];
        if (sender != gridConf.owner) {
            revert IOrderErrors.NotGridOwner();
        }

        // Oneshot grids cannot have their fee modified - fee is fixed by protocol
        if (gridConf.oneshot) {
            revert IOrderErrors.CannotModifyOneshotFee();
        }

        if (fee > MAX_FEE || fee < MIN_FEE) {
            revert IOrderErrors.InvalidGridFee();
        }

        gridConf.fee = fee;

        emit IOrderEvents.GridFeeChanged(sender, gridId, fee);
    }

    /// @notice Set the oneshot protocol fee in basis points
    /// @dev Only callable through GridEx contract
    /// @param self The grid state storage
    /// @param feeBps The new oneshot protocol fee in basis points
    function setOneshotProtocolFeeBps(GridState storage self, uint32 feeBps) internal {
        if (feeBps > MAX_FEE || feeBps < MIN_FEE) {
            revert IOrderErrors.InvalidGridFee();
        }
        self.oneshotProtocolFeeBps = feeBps;
    }

    /// @notice Get the current oneshot protocol fee in basis points
    /// @param self The grid state storage
    /// @return The oneshot protocol fee in basis points
    function getOneshotProtocolFeeBps(GridState storage self) internal view returns (uint32) {
        return self.oneshotProtocolFeeBps;
    }
}
