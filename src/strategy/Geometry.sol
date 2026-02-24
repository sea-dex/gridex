// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridStrategy} from "../interfaces/IGridStrategy.sol";
import {IGeometryErrors} from "../interfaces/IGeometryErrors.sol";
import {ProtocolConstants} from "../libraries/ProtocolConstants.sol";
import {FullMath} from "../libraries/FullMath.sol";

/// @title Geometry
/// @author GridEx Protocol
/// @notice Geometric pricing strategy for grid orders
/// @dev Price progression: price(i) = price0 * ratio^i
///      - ratio is scaled by 1e18
///      - ask requires ratio > 1e18 (increasing prices)
///      - bid requires ratio < 1e18 (decreasing prices)
contract Geometry is IGridStrategy {
    /// @notice Price multiplier for quote/base pricing precision.
    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;

    /// @notice Ratio multiplier for geometric progression.
    uint256 public constant RATIO_MULTIPLIER = 10 ** 18;

    /// @notice The GridEx contract address that can create strategies.
    address public immutable GRID_EX;

    /// @notice Geometry strategy parameters.
    struct GeometryStrategy {
        uint256 basePrice;
        uint256 ratio;
    }

    /// @notice Mapping from strategy key to geometric parameters.
    mapping(uint256 => GeometryStrategy) public strategies;

    /// @notice Emitted when a new geometry strategy is created.
    event GeometryStrategyCreated(bool isAsk, uint128 gridId, uint256 price0, uint256 ratio);

    modifier onlyGridEx() {
        require(msg.sender == GRID_EX, "Unauthorized");
        _;
    }

    /// @param _gridEx The GridEx contract address.
    constructor(address _gridEx) {
        require(_gridEx != address(0), "Invalid gridEx address");
        GRID_EX = _gridEx;
    }

    function gridIdKey(bool isAsk, uint128 gridId) internal pure returns (uint256) {
        if (isAsk) {
            return (uint256(ProtocolConstants.ASK_ORDER_FLAG) << 128) | uint256(gridId);
        }
        return uint256(gridId);
    }

    function _powRatio(uint256 ratio, uint128 exp) internal pure returns (uint256 result) {
        result = RATIO_MULTIPLIER;
        uint256 base = ratio;
        uint128 e = exp;

        while (e > 0) {
            if ((e & 1) != 0) {
                result = FullMath.mulDiv(result, base, RATIO_MULTIPLIER);
            }
            e >>= 1;
            if (e > 0) {
                base = FullMath.mulDiv(base, base, RATIO_MULTIPLIER);
            }
        }
    }

    function _priceAt(uint256 price0, uint256 ratio, uint128 idx) internal pure returns (uint256) {
        uint256 ratioPow = _powRatio(ratio, idx);
        return FullMath.mulDiv(price0, ratioPow, RATIO_MULTIPLIER);
    }

    /// @inheritdoc IGridStrategy
    function validateParams(bool isAsk, uint128 amt, bytes calldata data, uint32 count) external pure override {
        if (count < 1) revert IGeometryErrors.GeometryInvalidCount();

        (uint256 price0, uint256 ratio) = abi.decode(data, (uint256, uint256));
        if (price0 == 0 || ratio == 0) {
            revert IGeometryErrors.GeometryInvalidPriceOrRatio();
        }

        if (isAsk) {
            if (count > 1 && ratio <= RATIO_MULTIPLIER) {
                revert IGeometryErrors.GeometryAskRatioTooLow();
            }

            // Compute the highest ask price price0 * ratio^(count-1).
            // _priceAt reverts via FullMath.mulDiv on overflow, which prevents
            // creating grids whose high-order ask prices are not computable.
            uint256 highestAskPrice = _priceAt(price0, ratio, uint128(count - 1));

            // Verify reverse price for order 0 (the lowest reverse price) produces
            // non-zero quote
            uint256 reversePrice0 = FullMath.mulDiv(price0, RATIO_MULTIPLIER, ratio);
            if (FullMath.mulDivRoundingUp(uint256(amt), reversePrice0, PRICE_MULTIPLIER) == 0) {
                revert IGeometryErrors.GeometryAskZeroQuote();
            }

            // Verify highest ask price also produces non-zero quote
            if (FullMath.mulDivRoundingUp(uint256(amt), highestAskPrice, PRICE_MULTIPLIER) == 0) {
                revert IGeometryErrors.GeometryAskZeroQuote();
            }
        } else {
            if (count > 1 && ratio >= RATIO_MULTIPLIER) {
                revert IGeometryErrors.GeometryBidRatioTooHigh();
            }
            uint256 lastPrice = _priceAt(price0, ratio, uint128(count - 1));
            if (FullMath.mulDivRoundingUp(uint256(amt), lastPrice, PRICE_MULTIPLIER) == 0) {
                revert IGeometryErrors.GeometryBidZeroQuote();
            }
        }
    }

    /// @inheritdoc IGridStrategy
    function createGridStrategy(bool isAsk, uint128 gridId, bytes memory data) external override onlyGridEx {
        uint256 key = gridIdKey(isAsk, gridId);
        require(strategies[key].basePrice == 0, "Already exists");
        (uint256 price0, uint256 ratio) = abi.decode(data, (uint256, uint256));
        strategies[key] = GeometryStrategy({basePrice: price0, ratio: ratio});

        emit GeometryStrategyCreated(isAsk, gridId, price0, ratio);
    }

    /// @inheritdoc IGridStrategy
    function getPrice(bool isAsk, uint128 gridId, uint128 idx) external view override returns (uint256) {
        GeometryStrategy storage s = strategies[gridIdKey(isAsk, gridId)];
        return _priceAt(s.basePrice, s.ratio, idx);
    }

    /// @inheritdoc IGridStrategy
    function getReversePrice(bool isAsk, uint128 gridId, uint128 idx) external view override returns (uint256) {
        GeometryStrategy storage s = strategies[gridIdKey(isAsk, gridId)];
        if (idx == 0) {
            return FullMath.mulDiv(s.basePrice, RATIO_MULTIPLIER, s.ratio);
        }
        return _priceAt(s.basePrice, s.ratio, idx - 1);
    }
}
