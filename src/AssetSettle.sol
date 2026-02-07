// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Currency} from "./libraries/Currency.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/// @title AssetSettle
/// @author GridEx Protocol
/// @notice Handles asset settlement and transfers for the GridEx protocol
/// @dev Abstract contract providing internal functions for settling trades and transferring assets
contract AssetSettle {
    using SafeTransferLib for ERC20;

    /// @notice The WETH contract address
    address public immutable WETH;

    /// @notice Thrown when the paid amount is not enough
    error NotEnough();

    /// @notice Transfer token between pool and user. More refund, less supplement
    /// @dev Handles both ETH and ERC20 token settlements
    /// @param token The currency to settle
    /// @param addr The user address
    /// @param amount The required amount
    /// @param paid The amount already paid (for ETH)
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

    /// @notice Safely transfer ETH to an address
    /// @dev Reverts if the transfer fails
    /// @param to The recipient address
    /// @param value The amount of ETH to transfer
    // forge-lint: disable-next-line(mixed-case-function)
    function safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, "safeTransferETH: failed");
    }

    /// @notice Try to pay back ETH to an address, ignoring failures
    /// @dev Does not revert if the transfer fails (e.g., recipient is a contract that rejects ETH)
    /// @param to The recipient address
    /// @param value The amount of ETH to transfer
    // forge-lint: disable-next-line(mixed-case-function)
    function tryPaybackETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        success;
    }

    /// @notice Settle assets with support for ETH wrapping/unwrapping
    /// @dev Handles the exchange of inToken for outToken with optional ETH conversion
    /// @param inToken The token being received by the contract
    /// @param outToken The token being sent to the user
    /// @param addr The user address
    /// @param inAmt The amount of inToken to receive
    /// @param outAmt The amount of outToken to send
    /// @param paid The ETH amount paid (if applicable)
    /// @param flag Bit flags: 0x01 = inToken is ETH, 0x02 = outToken is ETH
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
                require(Currency.unwrap(inToken) == WETH, "Not WETH");
                IWETH(WETH).deposit{value: inAmt}();
                if (paid > inAmt) {
                    tryPaybackETH(addr, paid - inAmt);
                }
            } else {
                ERC20(Currency.unwrap(inToken)).safeTransferFrom(addr, address(this), inAmt);
            }

            // out token
            if (flag & 0x02 > 0) {
                require(Currency.unwrap(outToken) == WETH, "Not WETH");
                IWETH(WETH).withdraw(outAmt);
                safeTransferETH(addr, outAmt);
            } else {
                outToken.transfer(addr, outAmt);
            }
        }
    }

    /// @notice Transfer an asset to a recipient with optional ETH unwrapping
    /// @dev If flag is non-zero and token is WETH, unwraps to ETH before transfer
    /// @param token The token to transfer
    /// @param addr The recipient address
    /// @param amount The amount to transfer
    /// @param flag If non-zero and token is WETH, unwrap to ETH
    function transferAssetTo(Currency token, address addr, uint256 amount, uint32 flag) internal {
        if (flag == 0) {
            token.transfer(addr, amount);
        } else {
            require(Currency.unwrap(token) == WETH, "Not WETH");
            IWETH(WETH).withdraw(amount);
            safeTransferETH(addr, amount);
        }
    }

    /// @notice Transfer ERC20 tokens from a user to this contract
    /// @param token The token to transfer
    /// @param addr The sender address
    /// @param amount The amount to transfer
    function transferTokenFrom(Currency token, address addr, uint256 amount) internal {
        ERC20(Currency.unwrap(token)).safeTransferFrom(addr, address(this), amount);
    }

    /// @notice Transfer ETH from a user by wrapping it to WETH
    /// @dev Wraps the specified amount to WETH and refunds any excess ETH
    /// @param from The sender address (for refund)
    /// @param amt The amount to wrap to WETH
    /// @param paid The total ETH paid
    // forge-lint: disable-next-line(mixed-case-function)
    function transferETHFrom(address from, uint128 amt, uint128 paid) internal {
        IWETH(WETH).deposit{value: amt}();
        if (paid > amt) {
            safeTransferETH(from, paid - amt);
        }
    }
}
