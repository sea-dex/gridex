// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IGridEx} from "./interfaces/IGridEx.sol";
import {IGridOrder} from "./interfaces/IGridOrder.sol";
import {IGridStrategy} from "./interfaces/IGridStrategy.sol";
import {IOrderErrors} from "./interfaces/IOrderErrors.sol";
import {IOrderEvents} from "./interfaces/IOrderEvents.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {Lens} from "./Lens.sol";

abstract contract GridOrder is IOrderErrors, IOrderEvents, Lens {
    // uint32 public constant BID = 1;
    // uint32 public constant ASK = 2;

    uint32 public constant MIN_FEE = 100; // 0.01%
    uint32 public constant MAX_FEE = 10000; // 1%

    uint256 private constant OderIdMask = 0xffffffffffffffffffffffffffffffff;
    uint128 private constant AskOderMask = 0x80000000000000000000000000000000;

    uint32 public constant GridStatusNormal = 0;
    uint32 public constant GridStatusCanceled = 1;

    uint128 public nextBidOrderId = 1; // next grid order Id
    uint128 public nextAskOrderId = 0x80000000000000000000000000000001;

    mapping(uint128 orderId => IGridOrder.Order) public bidOrders;
    mapping(uint128 orderId => IGridOrder.Order) public askOrders;
    mapping(uint128 orderId => uint256) public orderStatus;

    uint128 public nextGridId = 1;
    mapping(uint128 gridId => IGridOrder.GridConfig) public gridConfigs;

    /// Validate grid order param
    function validateGridOrderParam(
        IGridOrder.GridOrderParam calldata param
    ) private pure {
        if (param.fee > MAX_FEE || param.fee < MIN_FEE) {
            revert InvalidGridFee();
        }

        unchecked {
            uint256 totalBaseAmt = uint256(param.baseAmount) *
                uint256(param.askOrderCount);
            if (totalBaseAmt > type(uint128).max) {
                revert ExceedMaxAmount();
            }

            // buy price should great than 0
            if (param.bidOrderCount > 0) {
                // require(param.bidOrderCount > 1, "E1");
                param.bidStrategy.validateParams(
                    false,
                    param.baseAmount,
                    param.bidData,
                    param.bidOrderCount
                );
                // the last order's price should great than 0
                // if (
                //     uint256(param.bidGap) * uint256(param.bidOrderCount - 1) >=
                //     uint256(param.bidPrice0)
                // ) {
                //     revert InvalidGridPrice();
                // }

                // // the first order's reverse price
                // if (
                //     uint256(param.bidPrice0) + uint256(param.bidGap) >
                //     uint256(type(uint256).max)
                // ) {
                //     revert InvalidGridPrice();
                // }
            }

            if (param.askOrderCount > 0) {
                // ASK orders
                param.askStrategy.validateParams(
                    true,
                    param.baseAmount,
                    param.askData,
                    param.askOrderCount
                );
                // sell price should less than uint256.max
                // require(param.askOrderCount > 1, "E2");

                // if (
                //     uint256(param.askPrice0) +
                //         uint256(param.askOrderCount - 1) *
                //         uint256(param.askGap) >
                //     uint256(type(uint256).max)
                // ) {
                //     revert InvalidGridPrice();
                // }

                // /// the first sell order's reverse price
                // if (param.askGap > param.askPrice0) {
                //     revert InvalidGridPrice();
                // }
            }
        }
    }

    function placeGridOrder(
        uint128 gridId,
        IGridOrder.GridOrderParam calldata param
    ) internal returns (uint128, uint128, uint128, uint128) {
        validateGridOrderParam(param);

        uint128 baseAmt = param.baseAmount;
        // uint96 orderId;
        uint128 startAskOrderId;
        uint128 startBidOrderId;
        uint128 quoteAmt;

        if (param.askOrderCount > 0) {
            startAskOrderId = nextAskOrderId;
            nextAskOrderId += param.askOrderCount;
            IGridStrategy(param.askStrategy).createGridStrategy(
                true,
                gridId,
                param.askData
            );
        }

        if (param.bidOrderCount > 0) {
            startBidOrderId = nextBidOrderId;
            nextBidOrderId += param.bidOrderCount;

            IGridStrategy(param.bidStrategy).createGridStrategy(
                false,
                gridId,
                param.bidData
            );

            // uint256 price0 = param.bidPrice0;
            // uint256 gap = param.bidGap;
            for (uint256 i = 0; i < param.bidOrderCount; ++i) {
                uint256 price = IGridStrategy(param.bidStrategy).getPrice(
                    false,
                    gridId,
                    uint128(i)
                );
                uint128 amt = calcQuoteAmount(baseAmt, price, false);
                quoteAmt += amt;
                // unchecked {
                //     // bidorders[orderId] = IGridOrder.Order({
                //     //     gridId: gridId,
                //     //     // orderId: orderId,
                //     //     amount: amt,
                //     //     revAmount: 0,
                //     //     price: price0
                //     //     // revPrice: price0 + gap
                //     // });
                //     // ++orderId;

                //     price0 -= gap;
                // }
            }
        }

        return (
            startAskOrderId,
            baseAmt * param.askOrderCount,
            startBidOrderId,
            quoteAmt
        );
    }

    /// calculate how many base can be filled with quoteAmt
    function calcBaseAmount(
        uint128 quoteAmt,
        uint256 price,
        bool roundUp
    ) public pure returns (uint256) {
        uint256 amt = roundUp
            ? FullMath.mulDivRoundingUp(
                uint256(quoteAmt),
                PRICE_MULTIPLIER,
                uint256(price)
            )
            : FullMath.mulDiv(
                uint256(quoteAmt),
                PRICE_MULTIPLIER,
                uint256(price)
            );

        if (amt == 0) {
            revert ZeroBaseAmt();
        }
        if (amt >= uint256(type(uint128).max)) {
            revert ExceedBaseAmt();
        }
        return amt;
    }

    /// Calculate sum quote amount for grid order
    function calcSumQuoteAmount(
        uint128 baseAmt,
        uint256 price0,
        uint256 gap,
        uint32 orderCount
    ) public pure returns (uint256 quoteAmt) {
        for (uint256 i = 0; i < orderCount; ++i) {
            uint128 amt = calcQuoteAmount(baseAmt, price0, false);

            quoteAmt += amt;
            price0 -= gap;
        }
    }

    function _createGridConfig(
        address maker,
        uint64 pairId,
        IGridOrder.GridOrderParam calldata param
    ) internal returns (uint128, IGridOrder.GridConfig storage) {
        uint128 gridId = nextGridId++;

        gridConfigs[gridId] = IGridOrder.GridConfig({
            owner: maker,
            askStrategy: param.askStrategy,
            bidStrategy: param.bidStrategy,
            profits: 0,
            gridId: gridId,
            baseAmt: param.baseAmount,
            // askGap: param.askGap,
            pairId: pairId,
            startAskOrderId: 0,
            startBidOrderId: 0,
            // startAskPrice: param.askPrice0,
            // startBidPrice: param.bidPrice0,
            askOrderCount: param.askOrderCount,
            bidOrderCount: param.bidOrderCount,
            // bidGap: param.bidGap,
            fee: param.fee,
            compound: param.compound,
            oneshot: param.oneshot,
            status: GridStatusNormal
        });

        return (gridId, gridConfigs[gridId]);
    }

    function isAskGridOrder(uint256 orderId) public pure returns (bool) {
        return orderId & AskOderMask > 0;
    }

    function extractGridIdOrderId(
        uint256 gridOrderId
    ) internal pure returns (uint128, uint128) {
        return (uint128(gridOrderId >> 128), uint128(gridOrderId & OderIdMask));
    }

    function calculateFees(
        uint128 vol,
        uint32 bps
    ) public pure returns (uint128 lpFee, uint128 protocolFee) {
        unchecked {
            uint128 fee = uint128((uint256(vol) * uint256(bps)) / 1000000);
            protocolFee = fee >> 1;
            lpFee = fee - protocolFee;
        }
    }

    function getOrderInfo(
        uint256 gridOrderId,
        bool forFill
    ) internal view returns (IGridOrder.OrderInfo memory orderInfo) {
        (uint128 gridId, uint128 orderId) = extractGridIdOrderId(gridOrderId);
        bool isAsk = isAskGridOrder(gridOrderId);
        IGridOrder.Order memory order = isAsk
            ? askOrders[orderId]
            : bidOrders[orderId];
        IGridOrder.GridConfig memory gridConf = gridConfigs[gridId];

        if (isAsk) {
            require(
                orderId >= gridConf.startAskOrderId &&
                    orderId < gridConf.startAskOrderId + gridConf.askOrderCount,
                "E3"
            );
        } else {
            require(
                orderId >= gridConf.startBidOrderId &&
                    orderId < gridConf.startBidOrderId + gridConf.bidOrderCount,
                "E4"
            );
        }

        if (
            (orderStatus[orderId] != GridStatusNormal) ||
            gridConf.status != GridStatusNormal
        ) {
            if (forFill) {
                revert OrderCanceled();
            }
            orderInfo.status = GridStatusCanceled;
        } else {
            orderInfo.status = GridStatusNormal;
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
                price = gridConf.bidStrategy.getPrice(
                    false,
                    gridId,
                    orderId - gridConf.startBidOrderId
                );
                orderInfo.amount = calcQuoteAmount(
                    gridConf.baseAmt,
                    price,
                    false
                );
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
            price = gridConf.askStrategy.getPrice(
                true,
                gridId,
                orderId - gridConf.startAskOrderId
            );
            orderInfo.price = price;
            orderInfo.revPrice = gridConf.askStrategy.getReversePrice(
                true,
                gridId,
                orderId - gridConf.startAskOrderId
            ); //price - gridConf.askGap;
        } else {
            if (price == 0) {
                // unchecked {
                //     price =
                //         gridConf.startBidPrice -
                //         (orderId - gridConf.startBidOrderId) *
                //         gridConf.bidGap;
                // }
                price = gridConf.bidStrategy.getPrice(
                    false,
                    gridId,
                    orderId - gridConf.startBidOrderId
                );
            }
            orderInfo.price = price;
            orderInfo.revPrice = gridConf.bidStrategy.getReversePrice(
                false,
                gridId,
                orderId - gridConf.startBidOrderId
            );
        }

        orderInfo.isAsk = isAsk;
        orderInfo.compound = gridConf.compound;
        orderInfo.oneshot = gridConf.oneshot;
        orderInfo.fee = gridConf.fee;
        orderInfo.pairId = gridConf.pairId;

        return orderInfo;
    }

    // should check order status by caller
    function getOrderAmountsForCancel(
        IGridOrder.GridConfig memory gridConf,
        uint128 orderId
    ) internal view returns (uint128 baseAmt, uint128 quoteAmt) {
        bool isAsk = isAskGridOrder(orderId);
        if (isAsk) {
            require(
                orderId >= gridConf.startAskOrderId &&
                    orderId < gridConf.startAskOrderId + gridConf.askOrderCount,
                "E5"
            );
        } else {
            require(
                orderId >= gridConf.startBidOrderId &&
                    orderId < gridConf.startBidOrderId + gridConf.bidOrderCount,
                "E6"
            );
        }

        IGridOrder.Order memory order = isAsk
            ? askOrders[orderId]
            : bidOrders[orderId];

        if (order.amount == 0 && order.revAmount == 0) {
            if (isAsk) {
                return (gridConf.baseAmt, 0);
            } else {
                uint256 price = gridConf.bidStrategy.getPrice(
                    false,
                    gridConf.gridId,
                    orderId - gridConf.startBidOrderId
                );
                // uint256 price = gridConf.startBidPrice -
                //     gridConf.bidGap *
                //     (orderId - gridConf.startBidOrderId);
                uint128 quoteVol = calcQuoteAmount(
                    gridConf.baseAmt,
                    price,
                    false
                );
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

    function completeOneShotOrder(uint128 orderId) internal {
        orderStatus[orderId] = GridStatusCanceled;
    }

    function _fillAskOrder(
        uint128 amt, // base token amt
        address taker,
        IGridOrder.OrderInfo memory orderInfo
    ) internal returns (IGridOrder.OrderFillResult memory result) {
        uint128 orderBaseAmt; // base token amount of the grid order
        uint128 orderQuoteAmt; // quote token amount of the grid order
        uint256 sellPrice;

        if (orderInfo.isAsk) {
            orderBaseAmt = orderInfo.amount;
            orderQuoteAmt = orderInfo.revAmount;
            sellPrice = orderInfo.price;
        } else {
            if (orderInfo.oneshot) {
                revert FillReversedOneShotOrder();
            }
            orderBaseAmt = orderInfo.revAmount;
            orderQuoteAmt = orderInfo.amount;
            sellPrice = orderInfo.revPrice;
        }

        if (amt > orderBaseAmt) {
            amt = orderBaseAmt;
        }
        if (amt == 0) {
            revert ZeroBaseAmt();
        }
        // quote volume taker will pay: quoteVol = filled * price
        uint128 quoteVol = calcQuoteAmount(amt, sellPrice, true);

        (result.lpFee, result.protocolFee) = calculateFees(
            quoteVol,
            orderInfo.fee
        );
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
                uint256 buyPrice = orderInfo.isAsk
                    ? orderInfo.revPrice
                    : orderInfo.price;
                uint128 quota = calcQuoteAmount(
                    orderInfo.baseAmt,
                    buyPrice,
                    false
                );
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
                completeOneShotOrder(orderInfo.orderId);
            }
        } else {
            result.orderAmt = orderQuoteAmt;
            result.orderRevAmt = orderBaseAmt;
        }

        result.filledAmt = amt;
        result.filledVol = quoteVol;

        emit FilledOrder(
            orderInfo.orderId,
            orderInfo.gridId,
            sellPrice, // ASK
            amt,
            quoteVol,
            orderBaseAmt,
            orderQuoteAmt,
            true,
            taker
        );
    }

    // bid order has no profit
    function _fillBidOrder(
        uint128 amt, // base token amt
        address taker,
        IGridOrder.OrderInfo memory orderInfo
    ) internal returns (IGridOrder.OrderFillResult memory result) {
        uint128 orderBaseAmt; // base token amount of the grid order
        uint128 orderQuoteAmt; // quote token amount of the grid order
        uint256 buyPrice;
        // uint256 orderPrice;

        if (orderInfo.isAsk) {
            if (orderInfo.oneshot) {
                revert FillReversedOneShotOrder();
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
        uint128 filledVol = calcQuoteAmount(amt, buyPrice, false);
        if (filledVol > orderQuoteAmt) {
            amt = uint128(calcBaseAmount(orderQuoteAmt, buyPrice, true));
            filledVol = orderQuoteAmt; // calcQuoteAmount(amt, buyPrice);
        }

        if (amt == 0) {
            revert ZeroBaseAmt();
        }

        (result.lpFee, result.protocolFee) = calculateFees(
            filledVol,
            orderInfo.fee
        );

        orderBaseAmt += amt;

        // avoid stacks too deep
        // {
        if (orderInfo.compound) {
            orderQuoteAmt -= filledVol - result.lpFee; // all quote reverse
        } else {
            // lpFee into profit
            result.profit = uint128(result.lpFee);
            orderQuoteAmt -= filledVol;
        }
        // }

        // update result
        result.filledAmt = amt;
        result.filledVol = filledVol;
        if (orderInfo.isAsk) {
            result.orderAmt = orderBaseAmt;
            result.orderRevAmt = orderQuoteAmt;
        } else {
            result.orderAmt = orderQuoteAmt;
            result.orderRevAmt = orderBaseAmt;
            if (orderInfo.oneshot && orderQuoteAmt == 0) {
                completeOneShotOrder(orderInfo.orderId);
            }
        }

        emit FilledOrder(
            orderInfo.orderId,
            orderInfo.gridId,
            buyPrice, // BID
            amt,
            filledVol,
            orderBaseAmt,
            orderQuoteAmt,
            false,
            taker
        );
    }
}
