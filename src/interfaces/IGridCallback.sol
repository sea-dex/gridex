// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./IGridOrder.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../libraries/Currency.sol";

/// @title IGridCallback
/// @author GridEx Protocol
/// @notice Callback interface for flash-swap style order filling
/// @dev Implement this interface to receive callbacks during order fills
interface IGridCallback {
    /// @notice Called after tokens are transferred out during an order fill
    /// @dev The callback must transfer the required inToken amount back to the GridEx contract
    /// @param inToken The ERC20 token address that must be paid (always ERC20, not ETH)
    /// @param outToken The ERC20 token address that was received (always ERC20, not ETH)
    /// @param inAmt The amount of inToken that must be transferred back
    /// @param outAmt The amount of outToken that was transferred out
    /// @param data Arbitrary data passed through from the fill function
    function gridFillCallback(address inToken, address outToken, uint128 inAmt, uint128 outAmt, bytes calldata data)
        external;
}
