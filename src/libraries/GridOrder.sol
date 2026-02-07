// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IGridOrder} from "../interfaces/IGridOrder.sol";
import {IGridStrategy} from "../interfaces/IGridStrategy.sol";
import {IOrderErrors} from "../interfaces/IOrderErrors.sol";
import {IOrderEvents} from "../interfaces/IOrderEvents.sol";

import {Lens} from "./Lens.sol";

/// @title GridOrder
/// @author GridEx Protocol
/// @notice Library for managing grid order state and operations
/// @dev Contains all logic for placing, filling, and canceling grid orders
library GridOrder {
    /// @notice Minimum fee in basis points (0.01%)
    uint32 public constant MIN_FEE = 100;
    
    /// @notice Maximum fee in basis points (10%)
    uint32 public constant MAX_FEE = 100000;

    /// @dev Mask for extracting order ID from grid order ID
    uint256 private constant ODER_ID_MASK = 0xffffffffffffffffffffffffffffffff;
    
    /// @dev Mask for identifying ask orders (high bit set)
    uint128 private constant ASK_ODER_MASK = 0x80000000000000000000000000000000;

    /// @dev Grid status: normal/active
    uint32 private constant GRID_STATUS_NORMAL = 0;
    
    /// @dev Grid status: canceled
    uint32 private constant GRID_STATUS_CANCELED = 1;

    /// @notice State structure for managing all grid orders
    /// @dev Stored in contract storage
    struct GridState {
        /// @notice Next grid ID to assign (starts from 1)
        uint128 nextGridId;
        /// @notice Next bid order ID to assign (starts from 1)
        uint128 nextBidOrderId;
        /// @notice Next ask order ID to assign (starts from 0x80000000000000000000000000000001)
        uint128 nextAskOrderId;
        /// @notice Mapping from grid order ID to order status
        mapping(uint256 gridOrderId => uint256) orderStatus;
        /// @notice Mapping from grid order ID to order data
        mapping(uint256 gridOrderId => IGridOrder.Order) orderInfos;
        /// @notice Mapping from grid ID to grid configuration
        mapping(uint256 gridId => IGridOrder.GridConfig) gridConfigs;
    }

    /// @notice Validate grid order parameters
    /// @dev Checks fee range and validates strategy parameters
    /// @param param The grid order parameters to validate
    function validateGridOrderParam(IGridOrder.GridOrderParam calldata param) private pure {
        if (param.fee > MAX_FEE || param.fee < MIN_FEE) {
            revert IOrderErrors.InvalidGridFee();
        }

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
    /// @param gridId The grid ID
    /// @param orderId The order ID within the grid
    /// @return id The combined grid order ID
    function toGridOrderId(uint128 gridId, uint128 orderId) public pure returns (uint256 id) {
        id = (uint256(gridId) << 128) | uint256(orderId);
    }

    /// @notice Check if an order ID represents an ask order
    /// @param orderId The order ID to check
    /// @return True if the order is an ask order
    function isAskGridOrder(uint256 orderId) public pure returns (bool) {
        return (orderId & ASK_ODER_MASK) > 0;
    }

    /// @notice Extract grid ID and order ID from a combined grid order ID
    /// @param gridOrderId The combined grid order ID
    /// @return The grid ID
    /// @return The order ID
    function extractGridIdOrderId(uint256 gridOrderId) internal pure returns (uint128, uint128) {
        // casting to 'uint128' is safe here
        // forge-lint: disable-next-line(unsafe-typecast)
        return (uint128(gridOrderId >> 128), uint128(gridOrderId & ODER_ID_MASK));
    }

    /// @notice Get order amounts for cancellation
    /// @dev Returns base and quote amounts to refund when canceling an order
    /// @param self The grid state storage
    /// @param gridConf The grid configuration
    /// @param orderId The order ID to cancel
    /// @return baseAmt The base token amount to refund
    /// @return quoteAmt The quote token amount to refund
    function getOrderAmountsForCancel(GridState storage self, IGridOrder.GridConfig memory gridConf, uint128 orderId)
        internal
        view
        returns (uint128 baseAmt, uint128 quoteAmt)
    {
        bool isAsk = isAskGridOrder(orderId);
        if (isAsk) {
            require(
                orderId >= gridConf.startAskOrderId && orderId < gridConf.startAskOrderId + gridConf.askOrderCount, "E1"
            );
        } else {
            require(
                orderId >= gridConf.startBidOrderId && orderId < gridConf.startBidOrderId + gridConf.bidOrderCount, "E2"
            );
        }

        IGridOrder.Order memory order = self.orderInfos[toGridOrderId(gridConf.gridId, orderId)];
        // ? askOrders[orderId]
        // : bidOrders[orderId];

        if (order.amount == 0 && order.revAmount == 0) {
            // not initialized
            if (isAsk) {
                return (gridConf.baseAmt, 0);
            } else {
                uint256 price =
                    gridConf.bidStrategy.getPrice(false, gridConf.gridId, orderId - gridConf.startBidOrderId);
                // uint256 price = gridConf.startBidPrice -
                //     gridConf.bidGap *
                //     (orderId - gridConf.startBidOrderId);
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

    /// @notice Initialize the grid state
    /// @dev Sets initial values for grid ID and order ID counters
    /// @param self The grid state storage to initialize
    function initialize(GridState storage self) internal {
        self.nextGridId = 1;
        self.nextBidOrderId = 1;
        self.nextAskOrderId = 0x80000000000000000000000000000001;
    }

    /// @notice Create a new grid configuration
    /// @param self The grid state storage
    /// @param pairId The trading pair ID
    /// @param maker The grid owner address
    /// @param param The grid order parameters
    /// @return The new grid ID
    function createGridConfig(
        GridState storage self,
        uint64 pairId,
        address maker,
        IGridOrder.GridOrderParam calldata param
    ) internal returns (uint128) {
        uint128 gridId = self.nextGridId++;

        self.gridConfigs[gridId] = IGridOrder.GridConfig({
            owner: maker,
            profits: 0,
            gridId: gridId,
            pairId: pairId,
            startAskOrderId: self.nextAskOrderId,
            startBidOrderId: self.nextBidOrderId,
            baseAmt: param.baseAmount,
            askStrategy: param.askStrategy,
            bidStrategy: param.bidStrategy,
            askOrderCount: param.askOrderCount,
            bidOrderCount: param.bidOrderCount,
            fee: param.fee,
            compound: param.compound,
            oneshot: param.oneshot,
            status: GRID_STATUS_NORMAL
        });

        return gridId;
    }

    /// @notice Place a new grid order
    /// @dev Creates grid config and calculates required token amounts
    /// @param self The grid state storage
    /// @param pairId The trading pair ID
    /// @param maker The grid owner address
    /// @param param The grid order parameters
    /// @return The grid ID
    /// @return The starting ask order ID (combined with grid ID)
    /// @return The starting bid order ID (combined with grid ID)
    /// @return The total base token amount required
    /// @return The total quote token amount required
    function placeGridOrder(
        GridState storage self,
        uint64 pairId,
        address maker,
        IGridOrder.GridOrderParam calldata param
    ) internal returns (uint128, uint256, uint256, uint128, uint128) {
        validateGridOrderParam(param);

        uint128 gridId = createGridConfig(self, pairId, maker, param);

        uint128 baseAmt = param.baseAmount;
        // uint96 orderId;
        uint128 startAskOrderId;
        uint128 startBidOrderId;
        uint128 quoteAmt;

        if (param.askOrderCount > 0) {
            startAskOrderId = self.nextAskOrderId;
            self.nextAskOrderId += param.askOrderCount;
            IGridStrategy(param.askStrategy).createGridStrategy(true, gridId, param.askData);
        }

        if (param.bidOrderCount > 0) {
            startBidOrderId = self.nextBidOrderId;
            self.nextBidOrderId += param.bidOrderCount;

            IGridStrategy(param.bidStrategy).createGridStrategy(false, gridId, param.bidData);

            // uint256 price0 = param.bidPrice0;
            // uint256 gap = param.bidGap;
            for (uint128 i = 0; i < param.bidOrderCount; ++i) {
                uint256 price = IGridStrategy(param.bidStrategy).getPrice(false, gridId, uint128(i));
                uint128 amt = Lens.calcQuoteAmount(baseAmt, price, false);
                quoteAmt += amt;
            }
        }

        return (
            gridId,
            toGridOrderId(gridId, startAskOrderId),
            toGridOrderId(gridId, startBidOrderId),
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
    function getOrderInfo(GridState storage self, uint256 gridOrderId, bool forFill)
        internal
        view
        returns (IGridOrder.OrderInfo memory orderInfo)
    {
        (uint128 gridId, uint128 orderId) = extractGridIdOrderId(gridOrderId);
        bool isAsk = isAskGridOrder(gridOrderId);
        IGridOrder.Order memory order = self.orderInfos[gridOrderId];
        IGridOrder.GridConfig memory gridConf = self.gridConfigs[gridId];

        if (isAsk) {
            require(
                orderId >= gridConf.startAskOrderId && orderId < gridConf.startAskOrderId + gridConf.askOrderCount, "E3"
            );
        } else {
            require(
                orderId >= gridConf.startBidOrderId && orderId < gridConf.startBidOrderId + gridConf.bidOrderCount, "E4"
            );
        }

        if ((self.orderStatus[gridOrderId] != GRID_STATUS_NORMAL) || gridConf.status != GRID_STATUS_NORMAL) {
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
        orderInfo.baseAmt = gridConf.baseAmt;
        if (order.amount == 0 && order.revAmount == 0) {
            // has not been initialized yet
            if (isAsk) {
                orderInfo.amount = gridConf.baseAmt;
            } else {
                // fixme!!!
                // unchecked {
                //     price =
                //         gridConf.startBidPrice -
                //         (orderId - gridConf.startBidOrderId) *
                //         gridConf.bidGap;
                // }
                price = gridConf.bidStrategy.getPrice(false, gridId, orderId - gridConf.startBidOrderId);
                orderInfo.amount = Lens.calcQuoteAmount(gridConf.baseAmt, price, false);
            }
        } else {
            orderInfo.amount = order.amount;
            orderInfo.revAmount = order.revAmount;
        }

        if (isAsk) {
            // unchecked {
            //     price =
            //         gridConf.startAskPrice +
            //         (orderId - gridConf.startAskOrderId) *
            //         gridConf.askGap;
            // }
            price = gridConf.askStrategy.getPrice(true, gridId, orderId - gridConf.startAskOrderId);
            orderInfo.price = price;
            // price - gridConf.askGap
            orderInfo.revPrice =
                gridConf.askStrategy.getReversePrice(true, gridId, orderId - gridConf.startAskOrderId);
        } else {
            if (price == 0) {
                // unchecked {
                //     price =
                //         gridConf.startBidPrice -
                //         (orderId - gridConf.startBidOrderId) *
                //         gridConf.bidGap;
                // }
                price = gridConf.bidStrategy.getPrice(false, gridId, orderId - gridConf.startBidOrderId);
            }
            orderInfo.price = price;
            orderInfo.revPrice =
                gridConf.bidStrategy.getReversePrice(false, gridId, orderId - gridConf.startBidOrderId);
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
    function completeOneShotOrder(GridState storage self, uint256 gridOrderId) internal {
        self.orderStatus[gridOrderId] = GRID_STATUS_CANCELED;
    }

    /// @notice Fill an ask order (taker buys base token)
    /// @dev Calculates fill amounts, fees, and updates order state
    /// @param self The grid state storage
    /// @param gridOrderId The grid order ID to fill
    /// @param amt The base token amount to fill
    /// @return result The fill result containing amounts and fees
    function fillAskOrder(
        GridState storage self,
        uint256 gridOrderId,
        uint128 amt // base token amt
    ) internal returns (IGridOrder.OrderFillResult memory result) {
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

        (result.lpFee, result.protocolFee) = Lens.calculateFees(quoteVol, orderInfo.fee);
        unchecked {
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
            // uint128 gridId = orderInfo.gridId;
            // IGridOrder.GridConfig storage gridConfig = gridConfigs[gridId];
            self.gridConfigs[orderInfo.gridId].profits += uint128(result.profit);
        }

        return result;
    }

    /// @notice Fill a bid order (taker sells base token)
    /// @dev Calculates fill amounts, fees, and updates order state
    /// @param self The grid state storage
    /// @param gridOrderId The grid order ID to fill
    /// @param amt The base token amount to fill
    /// @return result The fill result containing amounts and fees
    function fillBidOrder(
        GridState storage self,
        uint256 gridOrderId,
        uint128 amt // base token amt
    ) internal returns (IGridOrder.OrderFillResult memory result) {
        uint128 orderBaseAmt; // base token amount of the grid order
        uint128 orderQuoteAmt; // quote token amount of the grid order
        uint256 buyPrice;
        // uint256 orderPrice;

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

        // quote volume maker pays
        uint128 filledVol = Lens.calcQuoteAmount(amt, buyPrice, false);
        if (filledVol > orderQuoteAmt) {
            amt = uint128(Lens.calcBaseAmount(orderQuoteAmt, buyPrice, true));
            filledVol = orderQuoteAmt; // calcQuoteAmount(amt, buyPrice);
        }

        if (amt == 0) {
            revert IOrderErrors.ZeroBaseAmt();
        }

        (result.lpFee, result.protocolFee) = Lens.calculateFees(filledVol, orderInfo.fee);

        orderBaseAmt += amt;

        if (orderInfo.compound) {
            orderQuoteAmt -= filledVol - result.lpFee; // all quote reverse
        } else {
            // lpFee into profit
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
    /// @param gridId The grid ID to cancel
    /// @return The pair ID
    /// @return The total base token amount to refund
    /// @return The total quote token amount to refund
    function cancelGrid(GridState storage self, address sender, uint128 gridId)
        internal
        returns (uint64, uint256, uint256)
    {
        IGridOrder.GridConfig memory gridConf = self.gridConfigs[gridId];
        if (sender != gridConf.owner) {
            revert IOrderErrors.NotGridOwer();
        }

        if (gridConf.status != GRID_STATUS_NORMAL) {
            revert IOrderErrors.OrderCanceled();
        }

        uint256 baseAmt = 0;
        uint256 quoteAmt = 0;

        if (gridConf.askOrderCount > 0) {
            for (uint32 i = 0; i < gridConf.askOrderCount; ++i) {
                uint128 orderId = gridConf.startAskOrderId + i;
                uint256 gridOrderId = toGridOrderId(gridId, orderId);
                if (self.orderStatus[gridOrderId] != GRID_STATUS_NORMAL) {
                    continue;
                }

                // do not set orderStatus to save gas
                // orderStatus[orderId] = GridStatusCanceled;

                (uint128 ba, uint128 qa) = getOrderAmountsForCancel(self, gridConf, orderId);
                unchecked {
                    baseAmt += ba; // safe
                    quoteAmt += qa; // safe
                }
            }
        }

        if (gridConf.bidOrderCount > 0) {
            for (uint32 i = 0; i < gridConf.bidOrderCount; ++i) {
                uint128 orderId = gridConf.startBidOrderId + i;
                uint256 gridOrderId = toGridOrderId(gridId, orderId);
                if (self.orderStatus[gridOrderId] != GRID_STATUS_NORMAL) {
                    continue;
                }
                // do not set orderStatus to save gas
                // orderStatus[orderId] = GridStatusCanceled;

                (uint128 ba, uint128 qa) = getOrderAmountsForCancel(self, gridConf, orderId);
                unchecked {
                    baseAmt += ba; // safe
                    quoteAmt += qa; // safe
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
    /// @param gridId The grid ID containing the orders
    /// @param idList Array of grid order IDs to cancel
    /// @return The pair ID
    /// @return The total base token amount to refund
    /// @return The total quote token amount to refund
    function cancelGridOrders(GridState storage self, address sender, uint128 gridId, uint256[] memory idList)
        internal
        returns (uint64, uint256, uint256)
    {
        IGridOrder.GridConfig memory gridConf = self.gridConfigs[gridId];
        if (sender != gridConf.owner) {
            revert IOrderErrors.NotGridOwer();
        }

        if (gridConf.status != GRID_STATUS_NORMAL) {
            revert IOrderErrors.OrderCanceled();
        }

        uint256 baseAmt;
        uint256 quoteAmt;
        for (uint256 i = 0; i < idList.length; ++i) {
            uint256 gridOrderId = idList[i];
            (uint128 gid, uint128 orderId) = extractGridIdOrderId(gridOrderId);
            require(gid == gridId, "E5");

            if (self.orderStatus[gridOrderId] != GRID_STATUS_NORMAL) {
                revert IOrderErrors.OrderCanceled();
            }

            (uint128 ba, uint128 qa) = getOrderAmountsForCancel(self, gridConf, orderId);
            unchecked {
                baseAmt += ba;
                quoteAmt += qa;
            }
            self.orderStatus[gridOrderId] = GRID_STATUS_CANCELED;
            emit IOrderEvents.CancelGridOrder(msg.sender, orderId, gridId);
        }

        return (gridConf.pairId, baseAmt, quoteAmt);
    }

    /// @notice Modify the fee for a grid
    /// @dev Only the grid owner can modify the fee
    /// @param self The grid state storage
    /// @param sender The address requesting the modification (must be owner)
    /// @param gridId The grid ID to modify
    /// @param fee The new fee in basis points
    function modifyGridFee(GridState storage self, address sender, uint256 gridId, uint32 fee) internal {
        IGridOrder.GridConfig storage gridConf = self.gridConfigs[gridId];
        if (sender != gridConf.owner) {
            revert IOrderErrors.NotGridOwer();
        }

        if (fee > MAX_FEE || fee < MIN_FEE) {
            revert IOrderErrors.InvalidGridFee();
        }
        
        gridConf.fee = fee;

        emit IOrderEvents.GridFeeChanged(sender, gridId, fee);
    }
}
