// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

// forge-lint: disable-next-line(unaliased-plain-import)
import "../libraries/Currency.sol";

/// @title IGridExAdmin
/// @author GridEx Protocol
/// @notice Interface for AdminFacet: configuration and facet management
interface IGridExAdmin {
    /// @notice Emitted when a facet selector mapping is updated
    event FacetUpdated(bytes4 indexed selector, address indexed facet);

    /// @notice Set the WETH address
    // forge-lint: disable-next-line(mixed-case-function)
    function setWETH(address _weth) external;

    /// @notice Set or update a token's quote priority
    function setQuoteToken(Currency token, uint256 priority) external;

    /// @notice Set the whitelist status for a strategy contract
    function setStrategyWhitelist(address strategy, bool whitelisted) external;

    /// @notice Set the protocol fee for oneshot orders
    function setOneshotProtocolFeeBps(uint32 feeBps) external;

    /// @notice Pause trading operations
    function pause() external;

    /// @notice Unpause trading operations
    function unpause() external;

    /// @notice Rescue stuck ETH
    function rescueEth(address to, uint256 amount) external;

    /// @notice Register a single selector -> facet mapping
    function setFacet(bytes4 selector, address facet) external;

    /// @notice Register multiple selector -> facet mappings
    function batchSetFacet(bytes4[] calldata selectors, address[] calldata facets) external;

    /// @notice Transfer contract ownership
    function transferOwnership(address newOwner) external;
}
