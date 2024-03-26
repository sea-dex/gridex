// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title An interface for a contract that is capable of deploying Pairs
/// @notice A contract that constructs a pair must implement this to pass arguments to the pair
/// @dev This is used to avoid having constructor arguments in the pair contract, which results in the init code hash
/// of the pair being constant allowing the CREATE2 address of the pair to be cheaply computed on-chain
interface IPairDeployer {
    /// @notice Get the parameters to be used in constructing the pair, set transiently during pair creation.
    /// @dev Called by the pair constructor to fetch the parameters of the pair
    /// Returns factory The factory address
    /// Returns base The base token of the pair
    /// Returns quote The quote token of the pair
    /// Returns fee The fee collected upon every swap in the pair, denominated in hundredths of a bip
    function parameters()
        external
        view
        returns (address factory, address base, address quote, uint24 fee);
}
