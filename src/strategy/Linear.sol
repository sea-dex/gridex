// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IGridOrder} from "../interfaces/IGridOrder.sol";
import {IGridStrategy} from "../interfaces/IGridStrategy.sol";

// Linear strategy
contract Linear is IGridStrategy {
    struct LinearStrategy {
        uint160 basePrice;
        int160 gap; // bid order should be negative
    }

    mapping(uint128 => LinearStrategy) public strategies;

    function initGridStrategy(
        uint128 gridId,
        bytes memory data
    ) external override {
        (uint160 price0, int160 gap) = abi.decode(data, (uint160, int160));
        strategies[gridId] = LinearStrategy(price0, gap);
    }

    function validateParams(
        bool isAsk,
        bytes calldata data,
        uint32 count
    ) external pure override {
        require(count > 1, "L0");
        (uint160 price0, int160 gap) = abi.decode(data, (uint160, int160));
        if (isAsk) {
            require(gap > 0, "L1");
            require(uint160(gap) < price0, "L2");
            require(
                uint256(price0) + uint256(count - 1) * uint256(int256(gap)) <
                    uint256(type(uint160).max),
                "L3"
            );
        } else {
            require(gap < 0, "L4");
            require(
                uint256(price0) + uint256(-int256(gap)) <
                    uint256(type(uint160).max),
                "L5"
            );
            require(
                int256(uint256(price0)) +
                    int256(gap) *
                    int256(int32(count) - 1) >
                    0,
                "L6"
            );
        }
    }

    function getPrice(
        uint128 gridId,
        uint128 idx
    ) external view override returns (uint160) {
        LinearStrategy memory s = strategies[gridId];
        return uint160(int160(s.basePrice) + s.gap * int160(uint160(idx)));
    }

    function getReversePrice(
        uint128 gridId,
        uint128 idx
    ) external view override returns (uint160) {
        LinearStrategy memory s = strategies[gridId];
        return
            uint160(int160(s.basePrice) + s.gap * (int160(uint160(idx)) - 1));
    }
}
