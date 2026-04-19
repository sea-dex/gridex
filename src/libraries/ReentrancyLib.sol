// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

/// @title ReentrancyLib
/// @author GridEx Protocol
/// @notice Two-lock reentrancy guard using transient storage (EIP-1153, Cancun)
/// @dev Implements two separate lock mechanisms:
///      - STRICT lock: Binary lock for placeGrid/cancelGrid operations
///      - FILL lock: Depth-counting lock for fill operations (allows reentry)
///
///      Lock behavior:
///      - STRICT operations block if EITHER lock is active (mutual exclusion)
///      - FILL operations block if STRICT lock is active, but allow FILL reentry
///
///      This ensures:
///      1. placeGrid/cancelGrid and fill* are mutually non-reentrant
///      2. fill* can reenter other fill* operations (for flash-swap arbitrage)
///
///      Works correctly across delegatecall since transient storage is contract-context scoped.
library ReentrancyLib {
    /// @dev Transient storage slot for the STRICT lock (binary: 0 or 1)
    bytes32 private constant STRICT_LOCK_SLOT = keccak256("gridex.reentrancy.strict");

    /// @dev Transient storage slot for the FILL depth counter
    bytes32 private constant FILL_DEPTH_SLOT = keccak256("gridex.reentrancy.fill");

    /// @dev Maximum allowed FILL reentrancy depth to prevent unbounded recursion
    uint256 private constant MAX_FILL_DEPTH = 5;

    /// @dev Thrown when FILL reentrancy depth exceeds MAX_FILL_DEPTH
    ///      Selector: 0x8e6714a8
    error ReentrancyDepthExceeded();

    /// @dev Thrown when a STRICT operation is called while any lock is active
    ///      Selector: 0x3ee5aeb5 (same as ReentrancyGuardReentrantCall for compatibility)
    error StrictLockReentrantCall();

    /// @dev Thrown when a FILL operation is called while STRICT lock is active
    ///      Selector: 0x3ee5aeb5 (same as ReentrancyGuardReentrantCall for compatibility)
    error FillLockReentrantCall();

    // ═══════════════════════════════════════════════════════════════════════
    // STRICT LOCK: For placeGrid, cancelGrid, withdrawGridProfits
    // - Blocks if STRICT lock is active
    // - Blocks if FILL depth > 0
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Acquire the STRICT lock
    /// @dev Reverts if either STRICT lock or FILL depth is active.
    ///      This ensures STRICT operations cannot be called during any other operation.
    function _enterStrict() internal {
        bytes32 strictSlot = STRICT_LOCK_SLOT;
        bytes32 fillSlot = FILL_DEPTH_SLOT;
        assembly {
            // Check if STRICT lock is already held
            if tload(strictSlot) {
                // StrictLockReentrantCall() selector: 0x3ee5aeb5
                mstore(0, 0x3ee5aeb500000000000000000000000000000000000000000000000000000000)
                revert(0, 0x04)
            }
            // Check if FILL depth > 0 (any FILL operation in progress)
            if tload(fillSlot) {
                // StrictLockReentrantCall() selector: 0x3ee5aeb5
                mstore(0, 0x3ee5aeb500000000000000000000000000000000000000000000000000000000)
                revert(0, 0x04)
            }
            // Acquire STRICT lock
            tstore(strictSlot, 1)
        }
    }

    /// @notice Release the STRICT lock
    function _exitStrict() internal {
        bytes32 slot = STRICT_LOCK_SLOT;
        assembly {
            tstore(slot, 0)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FILL LOCK: For fillAskOrder, fillBidOrder, etc.
    // - Blocks if STRICT lock is active
    // - Allows reentry (depth counting up to MAX_FILL_DEPTH)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Enter FILL mode (increment depth counter)
    /// @dev Reverts if STRICT lock is active.
    ///      Allows nested re-entry from flash-swap callbacks for cross-order arbitrage.
    ///      Reverts if depth would exceed MAX_FILL_DEPTH.
    function _enterFill() internal {
        bytes32 strictSlot = STRICT_LOCK_SLOT;
        bytes32 fillSlot = FILL_DEPTH_SLOT;
        assembly {
            // Check if STRICT lock is held
            if tload(strictSlot) {
                // FillLockReentrantCall() selector: 0x3ee5aeb5
                mstore(0, 0x3ee5aeb500000000000000000000000000000000000000000000000000000000)
                revert(0, 0x04)
            }
            // Increment FILL depth
            let depth := tload(fillSlot)
            // Check depth < MAX_FILL_DEPTH (5)
            if iszero(lt(depth, 5)) {
                // ReentrancyDepthExceeded() selector: 0x8e6714a8
                mstore(0, 0x8e6714a800000000000000000000000000000000000000000000000000000000)
                revert(0, 0x04)
            }
            tstore(fillSlot, add(depth, 1))
        }
    }

    /// @notice Exit FILL mode (decrement depth counter)
    function _exitFill() internal {
        bytes32 slot = FILL_DEPTH_SLOT;
        assembly {
            let depth := tload(slot)
            tstore(slot, sub(depth, 1))
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LEGACY: Backward-compatible functions (deprecated, use _enterStrict/_enterFill)
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Transient storage slot for legacy depth counter
    bytes32 private constant REENTRANCY_SLOT = keccak256("gridex.reentrancy.guard");

    /// @notice Legacy: Increment the reentrancy depth counter
    /// @dev Deprecated: Use _enterFill() for fill operations, _enterStrict() for strict operations.
    function _enter() internal {
        bytes32 slot = REENTRANCY_SLOT;
        assembly {
            let depth := tload(slot)
            // Check depth < MAX_DEPTH (5)
            if iszero(lt(depth, 5)) {
                // ReentrancyDepthExceeded()
                mstore(0, 0x8e6714a800000000000000000000000000000000000000000000000000000000)
                revert(0, 0x04)
            }
            tstore(slot, add(depth, 1))
        }
    }

    /// @notice Legacy: Decrement the reentrancy depth counter
    /// @dev Deprecated: Use _exitFill() for fill operations, _exitStrict() for strict operations.
    function _exit() internal {
        bytes32 slot = REENTRANCY_SLOT;
        assembly {
            let depth := tload(slot)
            tstore(slot, sub(depth, 1))
        }
    }

    /// @notice Legacy: Revert if already inside a guarded call (depth > 0)
    /// @dev Deprecated: Use _enterStrict() which includes this check.
    function _guardNoReentry() internal view {
        bytes32 slot = REENTRANCY_SLOT;
        assembly {
            if tload(slot) {
                // ReentrancyGuardReentrantCall()
                mstore(0, 0x3ee5aeb500000000000000000000000000000000000000000000000000000000)
                revert(0, 0x04)
            }
        }
    }
}
