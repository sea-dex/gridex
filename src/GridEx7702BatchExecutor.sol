// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.33;

/// @title GridEx7702BatchExecutor
/// @notice Minimal ERC-7821 executor intended for EIP-7702 delegated EOAs.
/// @dev Executes calls sequentially in the authority account context.
contract GridEx7702BatchExecutor {
    error UnsupportedExecutionMode();
    error CallFailed(uint256 index, bytes reason);

    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    bytes32 internal constant MODE_DEFAULT = 0x0100000000000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant MODE_OPDATA = 0x0100000000007821000100000000000000000000000000000000000000000000;

    receive() external payable {}

    fallback() external payable {}

    function supportsExecutionMode(bytes32 mode) external pure returns (bool) {
        return mode == MODE_DEFAULT || mode == MODE_OPDATA;
    }

    function execute(bytes32 mode, bytes calldata executionData) external payable {
        if (mode == MODE_DEFAULT) {
            Call[] memory calls = abi.decode(executionData, (Call[]));
            _execute(calls);
            return;
        }

        if (mode == MODE_OPDATA) {
            (Call[] memory calls,) = abi.decode(executionData, (Call[], bytes));
            _execute(calls);
            return;
        }

        revert UnsupportedExecutionMode();
    }

    function _execute(Call[] memory calls) internal {
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory reason) = calls[i].target.call{value: calls[i].value}(calls[i].data);
            if (!success) revert CallFailed(i, reason);
        }
    }
}
