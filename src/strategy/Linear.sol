// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IGridOrder} from "../interfaces/IGridOrder.sol";
import {IGridStrategy} from "../interfaces/IGridStrategy.sol";
import {FullMath} from "../libraries/FullMath.sol";

// Linear strategy
contract Linear is IGridStrategy {
    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;

    struct LinearStrategy {
        uint256 basePrice;
        int256 gap; // bid order should be negative
    }

    mapping(uint256 => LinearStrategy) public strategies;

    function gridIdKey(
        bool isAsk,
        uint128 gridId
    ) internal pure returns (uint256) {
        if (isAsk) {
            return (1 << 128) | uint256(gridId);
        }
        return uint256(gridId);
    }

    function createGridStrategy(
        bool isAsk,
        uint128 gridId,
        bytes memory data
    ) external override {
        (uint256 price0, int256 gap) = abi.decode(data, (uint256, int256));
        strategies[gridIdKey(isAsk, gridId)] = LinearStrategy(price0, gap);
    }

    function validateParams(
        bool isAsk,
        uint128 amt,
        bytes calldata data,
        uint32 count
    ) external pure override {
        require(count > 1, "L0");
        (uint256 price0, int256 gap) = abi.decode(data, (uint256, int256));
        require(price0 > 0 && gap != 0, "L1");

        if (isAsk) {
            require(gap > 0, "L2");
            require(uint256(gap) < price0, "L3");
            require(
                uint256(price0) + uint256(count - 1) * uint256(int256(gap)) <
                    uint256(type(uint256).max),
                "L4"
            );
            require(
                FullMath.mulDivRoundingUp(
                    uint256(amt),
                    uint256(price0),
                    PRICE_MULTIPLIER
                ) > 0,
                "Q0"
            );
        } else {
            require(gap < 0, "L5");
            require(
                uint256(price0) + uint256(-int256(gap)) <
                    uint256(type(uint256).max),
                "L6"
            );
            int256 priceLast = int256(uint256(price0)) +
                int256(gap) *
                int256(int32(count) - 1);
            require(priceLast > 0, "L7");
            require(
                FullMath.mulDivRoundingUp(
                    uint256(amt),
                    uint256(priceLast),
                    PRICE_MULTIPLIER
                ) > 0,
                "Q1"
            );
        }
    }

    function getPrice(
        bool isAsk,
        uint128 gridId,
        uint128 idx
    ) external view override returns (uint256) {
        LinearStrategy memory s = strategies[gridIdKey(isAsk, gridId)];
        return uint256(int256(s.basePrice) + s.gap * int256(uint256(idx)));
    }

    function getReversePrice(
        bool isAsk,
        uint128 gridId,
        uint128 idx
    ) external view override returns (uint256) {
        LinearStrategy memory s = strategies[gridIdKey(isAsk, gridId)];
        return
            uint256(int256(s.basePrice) + s.gap * (int256(uint256(idx)) - 1));
    }
}
