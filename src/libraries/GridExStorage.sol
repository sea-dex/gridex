// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Currency} from "./Currency.sol";
import {IPair} from "../interfaces/IPair.sol";
import {GridOrder} from "./GridOrder.sol";

/// @title GridExStorage
/// @author GridEx Protocol
/// @notice Diamond-style namespaced storage for the GridEx protocol
/// @dev All facets share state through a single Layout struct at a fixed storage slot
library GridExStorage {
    bytes32 constant STORAGE_SLOT = keccak256("gridex.diamond.storage.v1");

    struct Layout {
        // --- Ownership ---
        address owner;
        // --- Core addresses ---
        address vault;
        address weth;
        // --- Pause state ---
        bool paused;
        // --- Pair management ---
        uint64 nextPairId;
        mapping(Currency => mapping(Currency => IPair.Pair)) getPair;
        mapping(uint64 => IPair.Pair) getPairById;
        mapping(Currency => uint256) quotableTokens;
        // --- Grid order state ---
        GridOrder.GridState gridState;
        // --- Strategy whitelist ---
        mapping(address => bool) whitelistedStrategies;
        // --- Facet routing ---
        mapping(bytes4 => address) selectorToFacet;
        mapping(address => bool) facetAllowlist;
    }

    /// @notice Returns the storage layout at the fixed diamond slot
    /// @return l The storage layout reference
    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
