// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./interfaces/IPair.sol";
import {Currency} from "./libraries/Currency.sol";

/// @title Pair
/// @author GridEx Protocol
/// @notice Manages trading pairs for the GridEx protocol
/// @dev Abstract contract that handles pair creation and lookup
abstract contract Pair is IPair {
    /// @notice The next pair ID to be assigned
    uint64 public nextPairId = 1;

    /// @notice Mapping from base token to quote token to pair info
    mapping(Currency => mapping(Currency => Pair)) public getPair;

    /// @notice Mapping from pair ID to pair info
    mapping(uint64 => Pair) public getPairById;

    /// @notice Mapping of tokens that can be used as quote tokens and their priorities
    /// @dev Higher priority means the token is preferred as quote token
    mapping(Currency => uint256) public quotableTokens;

    /// @notice Get the base and quote tokens for a pair
    /// @param pairId The pair ID to query
    /// @return base The base token address
    /// @return quote The quote token address
    function getPairTokens(uint64 pairId) public view override returns (Currency base, Currency quote) {
        Pair memory pair = getPairById[pairId];
        if (pair.pairId == 0) {
            revert InvalidPairId();
        }

        return (pair.base, pair.quote);
    }

    /// @notice Get the pair ID for a given base and quote token combination
    /// @param base The base token address
    /// @param quote The quote token address
    /// @return The pair ID, or 0 if the pair doesn't exist
    function getPairIdByTokens(Currency base, Currency quote) public view returns (uint64) {
        Pair memory pair = getPair[base][quote];
        return pair.pairId;
    }

    /// @notice Get an existing pair or create a new one
    /// @dev Validates that quote token is quotable and has higher priority than base
    /// @param base The base token address
    /// @param quote The quote token address
    /// @return pair The pair info struct
    function getOrCreatePair(Currency base, Currency quote) public override returns (Pair memory) {
        Pair memory pair = getPair[base][quote];
        if (pair.pairId > 0) {
            return pair;
        }

        // create pair
        if (quotableTokens[quote] == 0) {
            revert InvalidQuote();
        }

        if (quotableTokens[base] > quotableTokens[quote]) {
            revert InvalidQuote();
        }

        if (quotableTokens[base] == quotableTokens[quote]) {
            require(base < quote, "P1");
        }

        uint64 pairId = nextPairId++;
        pair.base = base;
        pair.quote = quote;
        pair.pairId = pairId;

        getPair[base][quote] = pair;
        getPairById[pairId] = pair;

        emit PairCreated(base, quote, pairId);

        return pair;
    }
}
