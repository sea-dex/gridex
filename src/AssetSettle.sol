// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Currency} from "./libraries/Currency.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract AssetSettle {
    using SafeTransferLib for ERC20;

    address public immutable WETH;

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


    // forge-lint: disable-next-line(mixed-case-function)
    function tryPaybackETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        success;
    }

    function settleAssetWith(
        Currency inToken,
        Currency outToken,
        address addr,
        uint256 inAmt,
        uint256 outAmt,
        uint256 paid,
        uint32 flag
    ) internal {
        if (flag == 0) {
            ERC20(Currency.unwrap(inToken)).safeTransferFrom(addr, address(this), inAmt);
            outToken.transfer(addr, outAmt);
        } else {
            // in token
            if (flag & 0x01 > 0) {
                assert(Currency.unwrap(inToken) == WETH);
                IWETH(WETH).deposit{value: inAmt}();
                if (paid > inAmt) {
                    tryPaybackETH(addr, paid - inAmt);
                }
            } else {
                ERC20(Currency.unwrap(inToken)).safeTransferFrom(addr, address(this), inAmt);
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

    function transferAssetTo(Currency token, address addr, uint256 amount, uint32 flag) internal {
        if (flag == 0) {
            token.transfer(addr, amount);
        } else {
            assert(Currency.unwrap(token) == WETH);
            IWETH(WETH).withdraw(amount);
            safeTransferETH(addr, amount);
        }
    }

    function transferTokenFrom(Currency token, address addr, uint256 amount) internal {
        ERC20(Currency.unwrap(token)).safeTransferFrom(addr, address(this), amount);
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function transferETHFrom(address from, uint128 amt, uint128 paid) internal {
        IWETH(WETH).deposit{value: amt}();
        if (paid > amt) {
            safeTransferETH(from, paid - amt);
        }
    }
}
