// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract Vault is Owned {
    using SafeTransferLib for ERC20;

    constructor() Owned(msg.sender) {}

    function withdrawERC20(address token, address to, uint256 amount) external onlyOwner {
        ERC20(token).safeTransfer(to, amount);
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function withdrawETH(address to, uint256 amount) external onlyOwner {
        (bool success,) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }
    
    receive() external payable {}
}
