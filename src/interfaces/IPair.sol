// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.33;

import {Currency} from "../libraries/Currency.sol";

/// @title IPair
/// @author GridEx Protocol
/// @notice Interface for managing trading pairs in the GridEx protocol
/// @dev Defines the pair structure and functions for pair management
interface IPair {
    /// @notice Thrown when quote token is invalid or has lower priority than base
    error InvalidQuote();

    /// @notice Thrown when pair ID is invalid or pair does not exist
    error InvalidPairId();

    /// @notice Emitted when a new trading pair is created
    /// @param base The base token of the pair
    /// @param quote The quote token of the pair
    /// @param pairId The unique identifier for the pair
    event PairCreated(Currency indexed base, Currency indexed quote, uint64 pairId);

    /// @notice Trading pair structure
    /// @dev Contains the base token, quote token, and unique pair identifier
    struct Pair {
        /// @notice The base token address
        Currency base;
        /// @notice The quote token address
        Currency quote;
        /// @notice The unique pair identifier
        uint64 pairId;
    }

    /// @notice Get the base and quote tokens for a given pair ID
    /// @param pairId The pair ID to query
    /// @return base The base token address
    /// @return quote The quote token address
    function getPairTokens(uint64 pairId) external view returns (Currency base, Currency quote);

    /// @notice Get the pair ID for a given base and quote token combination
    /// @param base The base token address
    /// @param quote The quote token address
    /// @return The pair ID, or 0 if the pair does not exist
    function getPairIdByTokens(Currency base, Currency quote) external view returns (uint64);

    /// @notice Get an existing pair or create a new one if it doesn't exist
    /// @dev Validates that quote token is quotable and has higher priority than base
    /// @param base The base token address
    /// @param quote The quote token address
    /// @return The pair structure containing base, quote, and pairId
    function getOrCreatePair(Currency base, Currency quote) external returns (Pair memory);
}
