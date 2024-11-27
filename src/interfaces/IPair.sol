// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {Currency} from "../libraries/Currency.sol";
interface IPair {
    /// @notice Thrown when quote token invalid
    error InvalidQuote();

    /// @notice Thrown when pair id invalid or pair not exist
    error InvalidPairId();

    /// @notice Emitted when a pair is created
    /// @param base The base token of the pair
    /// @param quote The quote token of the pair
    /// @param pairId The pair id
    event PairCreated(
        Currency indexed base,
        Currency indexed quote,
        uint64 pairId
    );

    /// @notice Pair
    struct Pair {
        /// base token
        Currency base;
        /// quote token
        Currency quote;
        /// pair id
        uint64 pairId;
    }

    /// @notice Get pair base/quote by pairId
    /// @param pairId pairId
    /// @return base base token address
    /// @return quote quote token address
    function getPairTokens(
        uint64 pairId
    ) external view returns (Currency base, Currency quote);

    /// @notice Get pair pairId by base and quote token
    /// @param base The base token address
    /// @param quote The quote token address
    /// @return pairId The pair id. 0 if pair not exist
    function getPairIdByTokens(
        Currency base,
        Currency quote
    ) external view returns (uint64);

    /// @notice Get pair by base/quote token, if not exist, create it
    /// @param base base token address
    /// @param quote quote token address
    /// @return Pair pair
    function getOrCreatePair(
        Currency base,
        Currency quote
    ) external returns (Pair memory);
}
