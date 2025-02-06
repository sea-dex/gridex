// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IFlashLoan {
    /// @notice Flashloan
    /// @param receiverAddress The receive address
    /// @param asset The asset address
    /// @param amount The amount to loan
    /// @param params The calldata for receive address
    function flashLoan(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params
    ) external;
}
