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
    // Order ID domains (uint16)
    // ---------------------------------------------------------------------

    /// @dev Ask orders are distinguished by having the high bit of a uint16 set.
    ///      Ask order IDs: 32768-65535 (0x8000-0xFFFF)
    ///      Bid order IDs: 0-32767 (0x0000-0x7FFF)
    uint16 internal constant ASK_ORDER_FLAG = 0x8000;

    /// @dev Ask order IDs start at 0x8000 (32768).
    uint16 internal constant ASK_ORDER_START_ID = 0x8000;

    /// @dev Bid order IDs start at 0.
    uint16 internal constant BID_ORDER_START_ID = 0;

    /// @dev Maximum orders per side (32768).
    uint16 internal constant MAX_ORDERS_PER_SIDE = 0x8000;

    // ---------------------------------------------------------------------
    // Grid ID (uint48)
    // ---------------------------------------------------------------------

    /// @dev Grid IDs start at 1.
    uint48 internal constant GRID_ID_START = 1;
}
