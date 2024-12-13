// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {IGridEx} from "./interfaces/IGridEx.sol";
import {IGridOrder} from "./interfaces/IGridOrder.sol";
import {IOrderErrors} from "./interfaces/IOrderErrors.sol";
import {IOrderEvents} from "./interfaces/IOrderEvents.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {Lens} from "./Lens.sol";
abstract contract GridOrder is IOrderErrors, IOrderEvents, Lens {
    uint32 public constant BID = 1;
    uint32 public constant ASK = 2;

    uint32 public constant MIN_FEE = 100; // 0.01%
    uint32 public constant MAX_FEE = 10000; // 1%

    uint96 public constant AskOderMask = 0x800000000000000000000000;

    uint96 public nextBidOrderId = 1; // next grid order Id
    uint96 public nextAskOrderId = 0x800000000000000000000001;

    /// Validate grid order param
    function validateGridOrderParam(
        IGridEx.GridOrderParam calldata param
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
                // the last order's price should great than 0
                if (
                    uint256(param.bidGap) * uint256(param.bidOrderCount - 1) >=
                    uint256(param.bidPrice0)
                ) {
                    revert InvalidGridPrice();
                }

                // the first order's reverse price
                if (
                    uint256(param.bidPrice0) + uint256(param.bidGap) >
                    uint256(type(uint160).max)
                ) {
                    revert InvalidGridPrice();
                }
            }
            if (param.askOrderCount > 0) {
                // ASK orders
                // sell price should less than uint160.max
                if (
                    uint256(param.askPrice0) +
                        uint256(param.askOrderCount - 1) *
                        uint256(param.askGap) >
                    uint256(type(uint160).max)
                ) {
                    revert InvalidGridPrice();
                }

                /// the first sell order's reverse price
                if (param.askGap > param.askPrice0) {
                    revert InvalidGridPrice();
                }
            }
        }
    }

    function placeGridOrder(
        uint96 gridId,
        IGridEx.GridOrderParam calldata param,
        mapping(uint96 orderId => IGridOrder.Order) storage askorders,
        mapping(uint96 orderId => IGridOrder.Order) storage bidorders
    ) internal returns (uint96, uint128, uint96, uint128) {
        validateGridOrderParam(param);

        uint128 baseAmt = param.baseAmount;
        uint96 orderId;
        uint96 startAskOrderId;
        uint96 startBidOrderId;
        uint128 quoteAmt;

        if (param.askOrderCount > 0) {
            orderId = startAskOrderId = nextAskOrderId;
            uint160 price0 = param.askPrice0;
            uint160 gap = param.askGap;
            for (uint256 i = 0; i < param.askOrderCount; ++i) {
                uint128 amt = baseAmt; // side == BID ? calcQuoteAmount(baseAmt, price0, false) : baseAmt;
                unchecked {
                    askorders[orderId] = IGridOrder.Order({
                        gridId: gridId,
                        // orderId: orderId,
                        amount: amt,
                        revAmount: 0,
                        price: price0
                        // revPrice: price0 - gap // side == BID ? price0 + gap : price0 - gap
                    });
                    ++orderId;
                    price0 += gap;
                }
            }
            nextAskOrderId = orderId;
        }

        if (param.bidOrderCount > 0) {
            orderId = startBidOrderId = nextBidOrderId;
            uint160 price0 = param.bidPrice0;
            uint160 gap = param.bidGap;
            for (uint256 i = 0; i < param.bidOrderCount; ++i) {
                uint128 amt = calcQuoteAmount(baseAmt, price0, false);
                unchecked {
                    bidorders[orderId] = IGridOrder.Order({
                        gridId: gridId,
                        // orderId: orderId,
                        amount: amt,
                        revAmount: 0,
                        price: price0
                        // revPrice: price0 + gap
                    });
                    ++orderId;

                    quoteAmt += amt;
                    price0 -= gap;
                }
            }
            nextBidOrderId = orderId;
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
        uint160 price,
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
        uint160 price0,
        uint160 gap,
        uint32 orderCount
    ) public pure returns (uint256 quoteAmt) {
        for (uint256 i = 0; i < orderCount; ++i) {
            uint128 amt = calcQuoteAmount(baseAmt, price0, false);

            quoteAmt += amt;
            price0 -= gap;
        }
    }

    function isAskGridOrder(uint96 orderId) public pure returns (bool) {
        return orderId & AskOderMask > 0;
    }

    function calculateFees(
        uint128 vol,
        uint32 bps
    ) public pure returns (uint128 lpFee, uint128 protocolFee) {
        unchecked {
            uint128 fee = uint128((uint256(vol) * uint256(bps)) / 1000000);
            protocolFee = fee >> 2;
            lpFee = fee - protocolFee;
        }
    }

    function _fillAskOrder(
        bool isAsk,
        uint96 orderId,
        uint128 amt, // base token amt
        address taker,
        IGridOrder.Order storage order,
        IGridOrder.GridConfig storage gridConfig
    ) internal returns (uint256, uint256, uint256) {
        uint128 orderBaseAmt; // base token amount of the grid order
        uint128 orderQuoteAmt; // quote token amount of the grid order
        uint160 sellPrice;

        if (isAsk) {
            orderBaseAmt = order.amount;
            orderQuoteAmt = order.revAmount;
            sellPrice = order.price;
        } else {
            orderBaseAmt = order.revAmount;
            orderQuoteAmt = order.amount;
            sellPrice = order.price + gridConfig.bidGap; // order.revPrice;
        }
        if (amt > orderBaseAmt) {
            amt = orderBaseAmt;
        }
        // quote volume taker will pay: quoteVol = filled * price
        uint128 quoteVol = calcQuoteAmount(amt, sellPrice, true);

        (uint128 lpFee, uint128 protocolFee) = calculateFees(
            quoteVol,
            gridConfig.fee
        );

        unchecked {
            orderBaseAmt -= amt;
        }
        // calculate orderQuoteAmt and update gridConfig
        {
            if (gridConfig.compound) {
                orderQuoteAmt += quoteVol + lpFee; // all quote reverse
            } else {
                // reverse order only buy base amt
                uint128 base = gridConfig.baseAmt;
                uint160 buyPrice = isAsk ? (order.price - gridConfig.askGap) : order.price;
                uint128 quota = calcQuoteAmount(base, buyPrice, false);
                // increase profit if sell quote amount > baseAmt * price
                unchecked {
                    if (orderQuoteAmt >= quota) {
                        gridConfig.profits += quoteVol + lpFee;
                    } else {
                        uint128 rev = orderQuoteAmt + quoteVol + lpFee;
                        if (rev > quota) {
                            orderQuoteAmt = quota;
                            gridConfig.profits += rev - quota;
                        } else {
                            orderQuoteAmt += quoteVol + lpFee;
                        }
                    }
                }
            }
        }

        // update storage order
        if (isAsk) {
            order.amount = orderBaseAmt;
            order.revAmount = orderQuoteAmt;
        } else {
            order.amount = orderQuoteAmt;
            order.revAmount = orderBaseAmt;
        }

        emit FilledOrder(
            orderId,
            order.gridId,
            sellPrice, // ASK
            amt,
            quoteVol,
            orderBaseAmt,
            orderQuoteAmt,
            true,
            taker
        );

        return (amt, quoteVol + lpFee + protocolFee, protocolFee);
    }

    function _fillBidOrder(
        bool isAsk,
        uint96 orderId,
        uint128 amt, // base token amt
        address taker,
        IGridOrder.Order storage order,
        IGridOrder.GridConfig storage gridConfig
    ) internal returns (uint256, uint256, uint256) {
        uint128 orderBaseAmt; // base token amount of the grid order
        uint128 orderQuoteAmt; // quote token amount of the grid order
        uint160 buyPrice;

        if (isAsk) {
            orderBaseAmt = order.amount;
            orderQuoteAmt = order.revAmount;
            buyPrice = order.price - gridConfig.askGap; // order.revPrice;
        } else {
            orderBaseAmt = order.revAmount;
            orderQuoteAmt = order.amount;
            buyPrice = order.price;
        }

        // quote volume maker pays
        uint128 filledVol = calcQuoteAmount(amt, buyPrice, false);
        if (filledVol > orderQuoteAmt) {
            amt = uint128(calcBaseAmount(orderQuoteAmt, buyPrice, true));
            filledVol = orderQuoteAmt; // calcQuoteAmount(amt, buyPrice);
        }
        (uint128 lpFee, uint128 protocolFee) = calculateFees(
            filledVol,
            gridConfig.fee
        );

        orderBaseAmt += amt;

        // avoid stacks too deep
        {
            if (gridConfig.compound) {
                orderQuoteAmt -= filledVol - lpFee; // all quote reverse
            } else {
                // lpFee into profit
                gridConfig.profits += uint128(lpFee);
                orderQuoteAmt -= filledVol;
            }
        }

        // update storage order
        if (isAsk) {
            order.amount = orderBaseAmt;
            order.revAmount = orderQuoteAmt;
        } else {
            order.amount = orderQuoteAmt;
            order.revAmount = orderBaseAmt;
        }
        emit FilledOrder(
            orderId,
            order.gridId,
            buyPrice, // BID
            amt,
            filledVol,
            orderBaseAmt,
            orderQuoteAmt,
            false,
            taker
        );

        return (amt, filledVol - lpFee - protocolFee, protocolFee);
    }
}
