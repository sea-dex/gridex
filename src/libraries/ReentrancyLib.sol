// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

/// @title ReentrancyLib
/// @author GridEx Protocol
/// @notice Depth-counting reentrancy guard using transient storage (EIP-1153, Cancun)
/// @dev Uses a depth counter instead of a binary lock to allow legitimate re-entry
///      from flash-swap callbacks (e.g., arbitrage across multiple grid orders).
///      Works correctly across delegatecall since transient storage is contract-context scoped.
///
///      Two guard levels:
///      - `_enter()` / `_exit()`: depth-counting, allows nested re-entry (for fill paths)
///      - `_guardNoReentry()`: reverts if already inside a guarded call (for cancel/withdraw)
library ReentrancyLib {
    /// @dev Transient storage slot for the reentrancy depth counter
    bytes32 private constant REENTRANCY_SLOT = keccak256("gridex.reentrancy.guard");

    /// @dev Maximum allowed reentrancy depth to prevent unbounded recursion
    uint256 private constant MAX_DEPTH = 5;

    /// @dev Thrown when reentrancy depth exceeds MAX_DEPTH
    error ReentrancyDepthExceeded();

    /// @dev Thrown when a non-reentrant function is called during reentrancy
    error ReentrancyGuardReentrantCall();

    /// @notice Increment the reentrancy depth counter
    /// @dev Allows nested re-entry from flash-swap callbacks for cross-order arbitrage.
    ///      Reverts if depth would exceed MAX_DEPTH.
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

    /// @notice Decrement the reentrancy depth counter
    function _exit() internal {
        bytes32 slot = REENTRANCY_SLOT;
        assembly {
            let depth := tload(slot)
            tstore(slot, sub(depth, 1))
        }
    }

    /// @notice Revert if already inside a guarded call (depth > 0)
    /// @dev Use this for operations that must NOT be called during a flash-swap callback,
    ///      such as cancel and withdraw operations.
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
