// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

/// @title ReentrancyLib
/// @author GridEx Protocol
/// @notice Reentrancy guard using transient storage (EIP-1153, Cancun)
/// @dev Works correctly across delegatecall since transient storage is contract-context scoped
library ReentrancyLib {
    /// @dev Transient storage slot for the reentrancy lock
    bytes32 private constant REENTRANCY_SLOT = keccak256("gridex.reentrancy.guard");

    error ReentrancyGuardReentrantCall();

    /// @notice Enter the reentrancy guard, reverting if already entered
    function _enter() internal {
        bytes32 slot = REENTRANCY_SLOT;
        uint256 locked;
        assembly {
            locked := tload(slot)
        }
        if (locked != 0) revert ReentrancyGuardReentrantCall();
        assembly {
            tstore(slot, 1)
        }
    }

    /// @notice Exit the reentrancy guard, clearing the lock
    function _exit() internal {
        bytes32 slot = REENTRANCY_SLOT;
        assembly {
            tstore(slot, 0)
        }
    }
}
