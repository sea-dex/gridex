// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IOrderEvents} from "../interfaces/IOrderEvents.sol";
import {IProtocolErrors} from "../interfaces/IProtocolErrors.sol";

import {Currency} from "../libraries/Currency.sol";
import {GridOrder} from "../libraries/GridOrder.sol";
import {GridExStorage} from "../libraries/GridExStorage.sol";

/// @title AdminFacet
/// @author GridEx Protocol
/// @notice Admin operations: config, facet management, ownership
/// @dev Delegatecalled by GridExRouter. Only owner can call these functions.
contract AdminFacet is IOrderEvents {
    using GridOrder for GridOrder.GridState;

    event QuotableTokenUpdated(Currency quote, uint256 priority);
    event FacetUpdated(bytes4 indexed selector, address indexed facet);
    event Paused(address account);
    event Unpaused(address account);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error EnforcedPause();
    error ExpectedPause();
    error NotOwner();

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() internal view {
        if (msg.sender != GridExStorage.layout().owner) revert NotOwner();
    }

    /// @notice Set the WETH address for this chain
    /// @param _weth The WETH contract address
    // forge-lint: disable-next-line(mixed-case-function)
    function setWETH(address _weth) external onlyOwner {
        if (_weth == address(0)) revert IProtocolErrors.InvalidAddress();
        GridExStorage.layout().weth = _weth;
    }

    /// @notice Set or update a token's quote priority
    /// @param token The token address to configure
    /// @param priority The priority value (0 = not quotable, higher = more preferred)
    function setQuoteToken(Currency token, uint256 priority) external onlyOwner {
        GridExStorage.layout().quotableTokens[token] = priority;
        emit QuotableTokenUpdated(token, priority);
    }

    /// @notice Set the whitelist status for a strategy contract
    /// @param strategy The strategy contract address
    /// @param whitelisted True to whitelist, false to remove
    function setStrategyWhitelist(address strategy, bool whitelisted) external onlyOwner {
        if (strategy == address(0)) revert IProtocolErrors.InvalidAddress();
        GridExStorage.layout().whitelistedStrategies[strategy] = whitelisted;
        emit StrategyWhitelistUpdated(msg.sender, strategy, whitelisted);
    }

    /// @notice Set the protocol fee for oneshot orders
    /// @param feeBps The new fee in basis points
    function setOneshotProtocolFeeBps(uint32 feeBps) external onlyOwner {
        GridExStorage.Layout storage l = GridExStorage.layout();
        uint32 oldFeeBps = l.gridState.oneshotProtocolFeeBps;
        l.gridState.setOneshotProtocolFeeBps(feeBps);
        emit OneshotProtocolFeeChanged(msg.sender, oldFeeBps, feeBps);
    }

    /// @notice Pause trading operations
    function pause() external onlyOwner {
        GridExStorage.Layout storage l = GridExStorage.layout();
        if (l.paused) revert EnforcedPause();
        l.paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause trading operations
    function unpause() external onlyOwner {
        GridExStorage.Layout storage l = GridExStorage.layout();
        if (!l.paused) revert ExpectedPause();
        l.paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Rescue stuck ETH from the contract
    /// @param to The recipient address
    /// @param amount The amount of ETH to rescue
    function rescueEth(address to, uint256 amount) external onlyOwner {
        (bool success,) = to.call{value: amount}("");
        if (!success) revert IProtocolErrors.ETHTransferFailed();
    }

    // ─── Facet management ────────────────────────────────────────────

    /// @notice Register a single selector -> facet mapping
    /// @param selector The function selector
    /// @param facet The facet address to route the selector to
    function setFacet(bytes4 selector, address facet) external onlyOwner {
        if (facet.code.length == 0) revert IProtocolErrors.InvalidAddress();
        GridExStorage.layout().selectorToFacet[selector] = facet;
        emit FacetUpdated(selector, facet);
    }

    /// @notice Register multiple selector -> facet mappings in batch
    /// @param selectors Array of function selectors
    /// @param facets Array of facet addresses (must match selectors length)
    function batchSetFacet(bytes4[] calldata selectors, address[] calldata facets) external onlyOwner {
        require(selectors.length == facets.length, "Length mismatch");
        GridExStorage.Layout storage l = GridExStorage.layout();
        for (uint256 i; i < selectors.length;) {
            if (facets[i].code.length == 0) revert IProtocolErrors.InvalidAddress();
            l.selectorToFacet[selectors[i]] = facets[i];
            emit FacetUpdated(selectors[i], facets[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Transfer contract ownership to a new address
    /// @param newOwner The new owner address
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert IProtocolErrors.InvalidAddress();
        GridExStorage.Layout storage l = GridExStorage.layout();
        address oldOwner = l.owner;
        l.owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
