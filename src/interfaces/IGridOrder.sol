// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "../libraries/Currency.sol";

interface IGridOrder {
    /// @dev Grid config
    struct GridConfig {
        address owner;
        uint128 profits; // quote token
        uint128 baseAmt;
        uint160 askGap;
        uint64 pairId;
        uint32 orderCount;
        uint160 bidGap;
        uint32 fee; // bps
        bool compound;
    }

    /// @dev Grid Order
    struct Order {
        // buy order: quote amount; sell order: base amount;
        uint128 amount;
        uint128 revAmount;
        // order price
        uint160 price;
        // grid id, or address if limit order
        uint96 gridId;
        // order reverse price
        // uint160 revPrice;
    }
}
