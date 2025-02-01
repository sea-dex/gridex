// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "../libraries/Currency.sol";

interface IGridOrder {
    /// Grid order param
    struct GridOrderParam {
        uint160 askPrice0;
        uint160 askGap;
        uint160 bidPrice0;
        uint160 bidGap;
        uint32 askOrderCount;
        uint32 bidOrderCount;
        uint32 fee; // bps
        bool compound;
        uint128 baseAmount;
    }

    /// @dev Grid config
    struct GridConfig {
        address owner;
        uint128 profits; // quote token
        uint128 baseAmt;
        uint128 startAskOrderId;
        uint128 startBidOrderId;
        uint160 startAskPrice;
        uint160 startBidPrice;
        uint160 askGap;
        uint64 pairId;
        uint32 askOrderCount;
        uint32 bidOrderCount;
        uint160 bidGap;
        uint32 fee; // bps
        uint128 gridId;
        bool compound;
        uint32 status; // 0: invalid; 1: normal; 2: canceled
    }

    /// @dev Grid Order
    struct Order {
        // buy order: quote amount; sell order: base amount;
        uint128 amount;
        uint128 revAmount;
        // order price
        // uint160 price;
        // grid id
        // uint96 gridId;
    }

    struct OrderInfo {
        // grid id
        bool isAsk;
        bool compound;
        uint32 fee;
        uint32 status; //  0: normal; 1: cancelled
        uint128 gridId;
        uint128 orderId;
        // buy order: quote amount; sell order: base amount;
        uint128 amount;
        uint128 revAmount;
        uint128 baseAmt;
        // order prices
        uint160 price;
        uint160 revPrice;
        // pairId
        uint64 pairId;
    }

    struct OrderFillResult {
        uint128 filledAmt; // base amount
        uint128 filledVol; // quote amount
        uint128 protocolFee; // protocol fee
        uint128 lpFee; // lp fee
        uint128 profit; // lp profit
        uint128 orderAmt; // order amount after filled
        uint128 orderRevAmt; // order revAmount after filled
    }
}
