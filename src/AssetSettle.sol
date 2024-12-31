// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "./interfaces/IWETH.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

abstract contract AssetSettle {
    address public immutable WETH;

    /// @notice Thrown when not enough
    error NotEnough();

    receive() external payable {}

    /// @dev Transfer token between pool and user. More refund, less supplement
    function _settle(
        Currency token,
        address addr,
        uint256 amount,
        uint256 paid
    ) internal {
        if (token.isAddressZero()) {
            if (paid > amount) {
                token.transfer(addr, paid - amount);
            } else if (paid < amount) {
                revert NotEnough();
            }
        } else {
            ERC20(Currency.unwrap(token)).transferFrom(
                addr,
                address(this),
                amount
            );
        }
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(
            success,
            "TransferHelper::safeTransferETH: ETH transfer failed"
        );
    }

    function _transferToken(
        Currency token,
        address addr,
        uint256 amount
    ) internal {
        ERC20(Currency.unwrap(token)).transferFrom(addr, address(this), amount);
    }

    function _transferETH(address from, uint128 amt, uint128 paid) internal {
        IWETH(WETH).deposit{value: amt}();
        if (paid > amt) {
            safeTransferETH(from, paid - amt);
        }
    }
}
