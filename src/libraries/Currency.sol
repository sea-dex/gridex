// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";
import {CustomRevert} from "../libraries/CustomRevert.sol";

/// @title Currency
/// @notice A custom type representing either native ETH (address(0)) or an ERC20 token address
/// @dev Wraps an address to provide type safety for currency operations
type Currency is address;

using {greaterThan as >, lessThan as <, greaterThanOrEqualTo as >=, equals as ==} for Currency global;
using CurrencyLibrary for Currency global;

/// @notice Check if two currencies are equal
/// @param currency The first currency
/// @param other The second currency
/// @return True if the currencies are equal
function equals(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) == Currency.unwrap(other);
}

/// @notice Check if one currency is greater than another (by address)
/// @param currency The first currency
/// @param other The second currency
/// @return True if currency > other
function greaterThan(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) > Currency.unwrap(other);
}

/// @notice Check if one currency is less than another (by address)
/// @param currency The first currency
/// @param other The second currency
/// @return True if currency < other
function lessThan(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) < Currency.unwrap(other);
}

/// @notice Check if one currency is greater than or equal to another (by address)
/// @param currency The first currency
/// @param other The second currency
/// @return True if currency >= other
function greaterThanOrEqualTo(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) >= Currency.unwrap(other);
}

/// @title CurrencyLibrary
/// @author GridEx Protocol
/// @notice Library for handling native ETH and ERC20 token transfers
/// @dev Provides unified interface for transferring and querying balances of both native ETH and ERC20 tokens
library CurrencyLibrary {
    /// @notice Thrown when a native ETH transfer fails
    /// @dev Additional context for ERC-7751 wrapped error
    error NativeTransferFailed();

    /// @notice Thrown when an ERC20 transfer fails
    /// @dev Additional context for ERC-7751 wrapped error
    error ERC20TransferFailed();

    /// @notice Constant representing native ETH (address(0))
    Currency public constant ADDRESS_ZERO = Currency.wrap(address(0));

    /// @notice Transfer currency to a recipient
    /// @dev Handles both native ETH and ERC20 transfers with gas-optimized assembly
    /// @param currency The currency to transfer
    /// @param to The recipient address
    /// @param amount The amount to transfer
    function transfer(Currency currency, address to, uint256 amount) internal {
        // altered from solmate SafeTransferLib
        // https://github.com/transmissions11/solmate/blob/44a9963d/src/utils/SafeTransferLib.sol
        // modified custom error selectors

        bool success;
        if (currency.isAddressZero()) {
            assembly ("memory-safe") {
                // Transfer the ETH and revert if it fails.
                success := call(gas(), to, amount, 0, 0, 0, 0)
            }
            // revert with NativeTransferFailed, containing the bubbled up error as an argument
            if (!success) {
                CustomRevert.bubbleUpAndRevertWith(to, bytes4(0), NativeTransferFailed.selector);
            }
        } else {
            assembly ("memory-safe") {
                // Get a pointer to some free memory.
                let fmp := mload(0x40)

                // Write the abi-encoded calldata into memory, beginning with the function selector.
                mstore(fmp, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
                // Append and mask the "to" argument.
                mstore(add(fmp, 4), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
                // Append the "amount" argument. Masking not required as it's a full 32 byte type.
                mstore(add(fmp, 36), amount)

                success :=
                    and(
                        // Set success to whether the call reverted, if not we check it either
                        // returned exactly 1 (can't just be non-zero data), or had no return data.
                        or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                        // We use 68 because the length of our calldata totals up like so: 4 + 32 * 2.
                        // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
                        // Counterintuitively, this call must be positioned second to the or() call in the
                        // surrounding and() call or else returndatasize() will be zero during the computation.
                        call(gas(), currency, 0, fmp, 68, 0, 32)
                    )

                // Now clean the memory we used
                mstore(fmp, 0) // 4 byte `selector` and 28 bytes of `to` were stored here
                mstore(add(fmp, 0x20), 0) // 4 bytes of `to` and 28 bytes of `amount` were stored here
                mstore(add(fmp, 0x40), 0) // 4 bytes of `amount` were stored here
            }
            // revert with ERC20TransferFailed, containing the bubbled up error as an argument
            if (!success) {
                CustomRevert.bubbleUpAndRevertWith(
                    Currency.unwrap(currency), IERC20Minimal.transfer.selector, ERC20TransferFailed.selector
                );
            }
        }
    }

    /// @notice Get the balance of this contract for a currency
    /// @param currency The currency to query
    /// @return The balance of this contract
    function balanceOfSelf(Currency currency) internal view returns (uint256) {
        if (currency.isAddressZero()) {
            return address(this).balance;
        } else {
            return IERC20Minimal(Currency.unwrap(currency)).balanceOf(address(this));
        }
    }

    /// @notice Get the balance of an address for a currency
    /// @param currency The currency to query
    /// @param owner The address to query the balance of
    /// @return The balance of the owner
    function balanceOf(Currency currency, address owner) internal view returns (uint256) {
        if (currency.isAddressZero()) {
            return owner.balance;
        } else {
            return IERC20Minimal(Currency.unwrap(currency)).balanceOf(owner);
        }
    }

    /// @notice Check if a currency is native ETH (address(0))
    /// @param currency The currency to check
    /// @return True if the currency is native ETH
    function isAddressZero(Currency currency) internal pure returns (bool) {
        return Currency.unwrap(currency) == Currency.unwrap(ADDRESS_ZERO);
    }

    /// @notice Convert a currency to a uint256 ID
    /// @param currency The currency to convert
    /// @return The uint256 representation of the currency address
    function toId(Currency currency) internal pure returns (uint256) {
        return uint160(Currency.unwrap(currency));
    }

    /// @notice Convert a uint256 ID to a currency
    /// @dev If the upper 12 bytes are non-zero, they will be zeroed out
    /// @param id The uint256 ID to convert
    /// @return The currency representation
    function fromId(uint256 id) internal pure returns (Currency) {
        // casting to 'uint160' is safe because id is address
        // forge-lint: disable-next-line(unsafe-typecast)
        return Currency.wrap(address(uint160(id)));
    }
}
