// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title Pausable
/// @author GridEx Protocol
/// @notice Abstract contract providing emergency pause functionality
/// @dev Inherit from this contract to add pause/unpause capabilities to your contract
abstract contract Pausable {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the contract is paused
    /// @param account The address that triggered the pause
    event Paused(address account);

    /// @notice Emitted when the contract is unpaused
    /// @param account The address that triggered the unpause
    event Unpaused(address account);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an operation is attempted while the contract is paused
    error EnforcedPause();

    /// @notice Thrown when an operation is attempted while the contract is not paused
    error ExpectedPause();

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether the contract is currently paused
    bool private _paused;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract in unpaused state
    constructor() {
        _paused = false;
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Modifier to make a function callable only when the contract is not paused
    /// @dev Reverts with EnforcedPause if the contract is paused
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /// @notice Modifier to make a function callable only when the contract is paused
    /// @dev Reverts with ExpectedPause if the contract is not paused
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns true if the contract is paused, and false otherwise
    /// @return True if paused, false otherwise
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reverts if the contract is paused
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /// @notice Reverts if the contract is not paused
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /// @notice Triggers stopped state
    /// @dev Should be called by an authorized account (e.g., owner)
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Returns to normal state
    /// @dev Should be called by an authorized account (e.g., owner)
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}
