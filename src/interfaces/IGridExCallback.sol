// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IGridExCallback {
    function gridExPlaceOrderCallback(address token, uint256 amount) external;
    function gridExSwapCallback(address token, uint256 amount) external;
}
