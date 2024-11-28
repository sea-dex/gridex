// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./interfaces/IPair.sol";

import "./libraries/TransferHelper.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";

abstract contract Pair is IPair {
    /// pair id
    uint64 public nextPairId = 1;

    /// pair index by base/quote address
    mapping(Currency => mapping(Currency => Pair)) public getPair;
    /// pair index by base/quote address
    mapping(uint64 => Pair) public getPairById;

    /// quotable tokens
    mapping(Currency => uint) public quotableTokens;

    function getPairTokens(
        uint64 pairId
    ) public view override returns (Currency base, Currency quote) {
        Pair memory pair = getPairById[pairId];
        if (pair.pairId == 0) {
            revert InvalidPairId();
        }

        return (pair.base, pair.quote);
    }

    function getPairIdByTokens(
        Currency base,
        Currency quote
    ) public view returns (uint64) {
        Pair memory pair = getPair[base][quote];
        return pair.pairId;
    }

    function getOrCreatePair(
        Currency base,
        Currency quote
    ) public override returns (Pair memory) {
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
