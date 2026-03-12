// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridStrategy} from "../interfaces/IGridStrategy.sol";
import {ProtocolConstants} from "../libraries/ProtocolConstants.sol";
import {FullMath} from "../libraries/FullMath.sol";

/// @title BaseStrategy
/// @author GridEx Protocol
/// @notice Base contract for grid pricing strategies
/// @dev Provides common functionality for strategy contracts
abstract contract BaseStrategy is IGridStrategy {
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

    /// @notice Creates a new BaseStrategy contract
    /// @param _gridEx The GridEx contract address
    constructor(address _gridEx) {
        require(_gridEx != address(0), "Invalid gridEx address");
        GRID_EX = _gridEx;
    }

    /// @notice Compute the storage key for a strategy
    /// @dev Ask strategies have high bit set to differentiate from bid strategies
    /// @param isAsk True if this is an ask strategy
    /// @param gridId The grid ID
    /// @return The storage key
    function gridIdKey(bool isAsk, uint48 gridId) internal pure returns (uint256) {
        if (isAsk) {
            return (uint256(ProtocolConstants.ASK_ORDER_FLAG) << 128) | uint256(gridId);
        }
        return uint256(gridId);
    }

    /// @notice Validate that (price * amt * count) / PRICE_MULTIPLIER does not overflow uint128
    /// @dev Used to ensure total quote amount calculations stay within bounds
    /// @param price The price (scaled by PRICE_MULTIPLIER)
    /// @param amt The base amount per order
    /// @param count The number of orders
    /// @return True if the quote amount is within uint128 bounds
    function _validateQuoteAmountNoOverflow(uint256 price, uint128 amt, uint32 count) internal pure returns (bool) {
        // First calculate price * amt, then multiply by count, then divide by PRICE_MULTIPLIER
        uint256 totalAmt = uint256(amt) * uint256(count);
        return FullMath.mulDiv(price, totalAmt, PRICE_MULTIPLIER) < type(uint128).max;
    }
}
