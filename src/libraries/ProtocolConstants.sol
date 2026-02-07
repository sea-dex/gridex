// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

/// @title ProtocolConstants
/// @author GridEx Protocol
/// @notice Centralized protocol constants to avoid scattered magic numbers.
library ProtocolConstants {
    // ---------------------------------------------------------------------
    // Quotes priority
    // ---------------------------------------------------------------------

    /// @dev Highest priority quote token (e.g., protocol USD). Used in `GridEx`.
    uint32 internal constant QUOTE_PRIORITY_USD = 1 << 20;

    /// @dev Secondary priority quote token (e.g., WETH). Used in `GridEx`.
    uint32 internal constant QUOTE_PRIORITY_WETH = 1 << 19;

    // ---------------------------------------------------------------------
    // Order ID domains
    // ---------------------------------------------------------------------

    /// @dev Ask orders are distinguished by having the high bit of a uint128 set.
    uint128 internal constant ASK_ORDER_FLAG = 0x80000000000000000000000000000000;

    /// @dev Ask order IDs start at `ASK_ORDER_FLAG | 1`.
    uint128 internal constant ASK_ORDER_START_ID = ASK_ORDER_FLAG | 1;

    /// @dev Bid order IDs start at 1.
    uint128 internal constant BID_ORDER_START_ID = 1;

    /// @dev Grid IDs start at 1.
    uint128 internal constant GRID_ID_START = 1;

    // ---------------------------------------------------------------------
    // Misc
    // ---------------------------------------------------------------------

    /// @dev Common uint128 upper bound.
    uint256 internal constant UINT128_EXCLUSIVE_UPPER_BOUND = 1 << 128;
}
