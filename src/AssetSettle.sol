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

    function _settleAssetWith(
        Currency inToken,
        Currency outToken,
        address addr,
        uint256 inAmt,
        uint256 outAmt,
        uint256 paid,
        uint32 flag
    ) internal {
        if (flag == 0) {
            ERC20(Currency.unwrap(inToken)).transferFrom(addr, address(this), inAmt);
            outToken.transfer(addr, outAmt);
        } else {
            // in token
            if (flag & 0x01 > 0) {
                assert(Currency.unwrap(inToken) == WETH);
                IWETH(WETH).deposit{value: inAmt}();
                if (paid > inAmt) {
                    safeTransferETH(addr, paid - inAmt);
                }
            } else {
                ERC20(Currency.unwrap(inToken)).transferFrom(addr, address(this), inAmt);
            }

            // out token
            if (flag & 0x02 > 0) {
                assert(Currency.unwrap(outToken) == WETH);
                IWETH(WETH).withdraw(outAmt);
                safeTransferETH(addr, outAmt);
            } else {
                outToken.transfer(addr, outAmt);
            }
        }
    }

    function _transferAssetTo(
        Currency token,
        address addr,
        uint256 amount,
        uint32 flag
    ) internal {
        if (flag == 0) {
            token.transfer(addr, amount);
        } else {
            assert(Currency.unwrap(token) == WETH);
            IWETH(WETH).withdraw(amount);
            safeTransferETH(addr, amount);
        }
    }

    function _transferTokenFrom(
        Currency token,
        address addr,
        uint256 amount
    ) internal {
        ERC20(Currency.unwrap(token)).transferFrom(addr, address(this), amount);
    }

    function _transferETHFrom(address from, uint128 amt, uint128 paid) internal {
        IWETH(WETH).deposit{value: amt}();
        if (paid > amt) {
            safeTransferETH(from, paid - amt);
        }
    }
}
