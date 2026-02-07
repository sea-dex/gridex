// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Currency} from "./Currency.sol";
import {IWETH} from "../interfaces/IWETH.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

library AssetSettle {
    using SafeTransferLib for ERC20;

    /// @notice Thrown when not enough
    error NotEnough();

    /// @dev Transfer token between pool and user. More refund, less supplement
    function settle(Currency token, address addr, uint256 amount, uint256 paid) internal {
        if (token.isAddressZero()) {
            if (paid > amount) {
                token.transfer(addr, paid - amount);
            } else if (paid < amount) {
                revert NotEnough();
            }
        } else {
            ERC20(Currency.unwrap(token)).safeTransferFrom(addr, address(this), amount);
        }
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, "TransferHelper::safeTransferETH: ETH transfer failed");
    }

    function settleAssetWith(
        Currency inToken,
        Currency outToken,
        address addr,
        uint256 inAmt,
        uint256 outAmt,
        uint256 paid,
        address weth,
        uint32 flag
    ) internal {
        if (flag == 0) {
            ERC20(Currency.unwrap(inToken)).safeTransferFrom(addr, address(this), inAmt);
            outToken.transfer(addr, outAmt);
        } else {
            // in token
            if (flag & 0x01 > 0) {
                assert(Currency.unwrap(inToken) == weth);
                IWETH(weth).deposit{value: inAmt}();
                if (paid > inAmt) {
                    safeTransferETH(addr, paid - inAmt);
                }
            } else {
                ERC20(Currency.unwrap(inToken)).safeTransferFrom(addr, address(this), inAmt);
            }

            // out token
            if (flag & 0x02 > 0) {
                assert(Currency.unwrap(outToken) == weth);
                IWETH(weth).withdraw(outAmt);
                safeTransferETH(addr, outAmt);
            } else {
                outToken.transfer(addr, outAmt);
            }
        }
    }

    function transferAssetTo(Currency token, address addr, uint256 amount, address weth, uint32 flag) internal {
        if (flag == 0) {
            token.transfer(addr, amount);
        } else {
            assert(Currency.unwrap(token) == weth);
            IWETH(weth).withdraw(amount);
            safeTransferETH(addr, amount);
        }
    }

    function transferTokenFrom(Currency token, address addr, uint256 amount) internal {
        ERC20(Currency.unwrap(token)).safeTransferFrom(addr, address(this), amount);
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function transferETHFrom(address from, address weth, uint128 amt, uint128 paid) internal {
        IWETH(weth).deposit{value: amt}();
        if (paid > amt) {
            safeTransferETH(from, paid - amt);
        }
    }
}
