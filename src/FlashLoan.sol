// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IFlashLoan} from "./interfaces/IFlashLoan.sol";
import {IFlashLoanReceiver} from "./interfaces/IFlashLoanReceiver.sol";
import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";

import {TransferHelper} from "./libraries/TransferHelper.sol";

abstract contract FlashLoan is IFlashLoan {
    uint256 private loanLocked = 1;
    bool public flashLoanEnable = true;
    uint32 public flashLoanRate = 10; // 0.001%

    mapping(address => uint256) public loanFees;

    event FlashLoanEvent(
        address indexed target,
        address initiator,
        address indexed asset,
        uint256 amount,
        uint256 premium
    );

    /// @inheritdoc IFlashLoan
    function flashLoan(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params
    ) public override {
        require(flashLoanEnable, "F1");
        require(loanLocked == 1, "F2");
        require(amount > 0, "F3");
        require(receiverAddress != address(0), "F4");
        require(asset != address(0), "F5");

        uint256 premium = (amount * flashLoanRate) / 1000000;

        loanLocked = 2;
        loanFees[asset] += premium;
        TransferHelper.safeTransfer(
            IERC20Minimal(asset),
            receiverAddress,
            amount
        );

        require(
            IFlashLoanReceiver(receiverAddress).executeOperation(
                asset,
                amount,
                premium,
                msg.sender,
                params
            ),
            "F6"
        );

        TransferHelper.safeTransferFrom(
            IERC20Minimal(asset),
            receiverAddress,
            address(this),
            amount + premium
        );

        loanLocked = 1;

        emit FlashLoanEvent(
            receiverAddress,
            msg.sender,
            asset,
            amount,
            premium
        );
    }
}
