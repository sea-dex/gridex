// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// import {IGridOrder} from "../interfaces/IGridOrder.sol";
import {IGridStrategy} from "../interfaces/IGridStrategy.sol";
import {FullMath} from "../libraries/FullMath.sol";

/// @title Linear
/// @author GridEx Protocol
/// @notice Linear pricing strategy for grid orders
/// @dev Implements IGridStrategy with linear price progression (constant price gap between orders)
contract Linear is IGridStrategy {
    /// @notice Price multiplier for fixed-point arithmetic (10^36)
    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;

    /// @notice The GridEx contract address that can create strategies
    address public immutable GRID_EX;

    /// @notice Ensures only the GridEx contract can call the function
    function _onlyGridEx() internal view {
        require(msg.sender == GRID_EX, "Unauthorized");
    }

    /// @notice Modifier to restrict access to GridEx contract only
    modifier onlyGridEx() {
        _onlyGridEx();
        _;
    }

    /// @notice Creates a new Linear strategy contract
    /// @param _gridEx The GridEx contract address
    constructor(address _gridEx) {
        require(_gridEx != address(0), "Invalid gridEx address");
        GRID_EX = _gridEx;
    }

    /// @notice Emitted when a new linear strategy is created
    /// @param isAsk True if this is an ask strategy, false for bid
    /// @param gridId The grid ID this strategy belongs to
    /// @param price0 The base price (first order price)
    /// @param gap The price gap between consecutive orders
    event LinearStrategyCreated(
        bool isAsk,
        uint128 gridId,
        uint256 price0,
        int256 gap
    );

    /// @notice Linear strategy parameters
    /// @dev Stored for each grid to calculate order prices
    struct LinearStrategy {
        /// @notice The base price (price of first order)
        uint256 basePrice;
        /// @notice The price gap between orders (negative for bid orders)
        int256 gap;
    }

    /// @notice Mapping from strategy key to strategy parameters
    /// @dev Key is computed from isAsk and gridId
    mapping(uint256 => LinearStrategy) public strategies;

    /// @notice Compute the storage key for a strategy
    /// @dev Ask strategies have high bit set to differentiate from bid strategies
    /// @param isAsk True if this is an ask strategy
    /// @param gridId The grid ID
    /// @return The storage key
    function gridIdKey(
        bool isAsk,
        uint128 gridId
    ) internal pure returns (uint256) {
        if (isAsk) {
            return (1 << 128) | uint256(gridId);
        }
        return uint256(gridId);
    }

    /// @inheritdoc IGridStrategy
    function createGridStrategy(
        bool isAsk,
        uint128 gridId,
        bytes memory data
    ) external override onlyGridEx {
        uint256 key = gridIdKey(isAsk, gridId);
        require(strategies[key].basePrice == 0, "Already exists");
        (uint256 price0, int256 gap) = abi.decode(data, (uint256, int256));
        strategies[key] = LinearStrategy({basePrice: price0, gap: gap});

        emit LinearStrategyCreated(isAsk, gridId, price0, gap);
    }

    /// @inheritdoc IGridStrategy
    function validateParams(
        bool isAsk,
        uint128 amt,
        bytes calldata data,
        uint32 count
    ) external pure override {
        require(count >= 1, "L0");
        (uint256 price0, int256 gap) = abi.decode(data, (uint256, int256));
        require(price0 > 0 && price0 < (1<<128) && gap != 0, "L1");

        if (isAsk) {
            require(gap > 0, "L2");
            // casting to 'uint256' is safe because gap > 0
            // forge-lint: disable-next-line(unsafe-typecast)
            require(uint256(gap) < price0, "L3");
            require(
                // casting to 'uint256' is safe because gap > 0
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256(price0) + uint256(count - 1) * uint256(int256(gap)) <
                    uint256(type(uint256).max),
                "L4"
            );
            require(
                FullMath.mulDivRoundingUp(
                    uint256(amt),
                    // casting to 'uint256' is safe because gap > 0
                    // forge-lint: disable-next-line(unsafe-typecast)
                    uint256(price0 - uint256(gap)),
                    PRICE_MULTIPLIER
                ) > 0,
                "Q0"
            );
        } else {
            require(gap < 0, "L5");
            require(
                // casting to 'uint256' is safe because gap < 0
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256(price0) + uint256(-int256(gap)) <
                    uint256(type(uint256).max),
                "L6"
            );
            // casting to 'uint256' is safe because price0 < 1<<128
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 priceLast = int256(uint256(price0)) +
                int256(gap) *
                int256(uint256(count) - 1);
            require(priceLast > 0, "L7");
            require(
                FullMath.mulDivRoundingUp(
                    uint256(amt),
                    // forge-lint: disable-next-line(unsafe-typecast)
                    uint256(priceLast),
                    PRICE_MULTIPLIER
                ) > 0,
                "Q1"
            );
        }
    }

    /// @inheritdoc IGridStrategy
    function getPrice(
        bool isAsk,
        uint128 gridId,
        uint128 idx
    ) external view override returns (uint256) {
        LinearStrategy memory s = strategies[gridIdKey(isAsk, gridId)];
        return uint256(int256(s.basePrice) + s.gap * int256(uint256(idx)));
    }

    /// @inheritdoc IGridStrategy
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
