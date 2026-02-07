// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./IGridStrategy.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../libraries/Currency.sol";

interface IGridOrder {
    /// Grid order param
    struct GridOrderParam {
        IGridStrategy askStrategy;
        IGridStrategy bidStrategy;
        bytes askData;
        bytes bidData;
        // uint256 askPrice0;
        // uint256 askGap;
        // uint256 bidPrice0;
        // uint256 bidGap;
        uint32 askOrderCount;
        uint32 bidOrderCount;
        uint32 fee; // bps
        bool compound;
        bool oneshot;
        uint128 baseAmount;
    }

    /// @dev Grid config
    struct GridConfig {
        address owner;
        IGridStrategy askStrategy;
        IGridStrategy bidStrategy;
        uint128 profits; // quote token
        uint128 baseAmt;
        uint128 startAskOrderId;
        uint128 startBidOrderId;
        uint128 gridId;
        uint64 pairId;
        uint32 askOrderCount;
        uint32 bidOrderCount;
        uint32 fee; // bps
        bool compound;
        bool oneshot;
        uint32 status; // 0: invalid; 1: normal; 2: canceled
    }

    /// @dev Grid Order
    struct Order {
        // buy order: quote amount; sell order: base amount;
        uint128 amount;
        uint128 revAmount;
    }

    struct OrderInfo {
        // grid id
        bool isAsk;
        bool compound;
        bool oneshot;
        uint32 fee;
        uint32 status; //  0: normal; 1: cancelled
        uint128 gridId;
        uint128 orderId;
        // buy order: quote amount; sell order: base amount;
        uint128 amount;
        uint128 revAmount;
        uint128 baseAmt;
        // order prices
        uint256 price;
        uint256 revPrice;
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
        uint64 pairId; // the pairId
    }
}
