// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

abstract contract AssetSettle {
    /// @notice Thrown when not enough
    error NotEnough();

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
}
