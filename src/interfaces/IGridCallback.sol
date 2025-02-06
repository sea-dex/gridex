// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "./IGridOrder.sol";
import "../libraries/Currency.sol";

interface IGridCallback {
    /// @notice inToken and outToken is ALWAYS ERC20 tokens
    function gridFillCallback(
        address inToken,
        address outToken,
        uint128 inAmt,
        uint128 outAmt,
        bytes calldata data
    ) external;
}
