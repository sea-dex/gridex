// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "./interfaces/IGridOrder.sol";
import {IProtocolErrors} from "./interfaces/IProtocolErrors.sol";

import {Currency} from "./libraries/Currency.sol";
import {GridOrder} from "./libraries/GridOrder.sol";
import {GridExStorage} from "./libraries/GridExStorage.sol";
import {ReentrancyLib} from "./libraries/ReentrancyLib.sol";

/// @title GridExRouter
/// @author GridEx Protocol
/// @notice Hybrid Router — explicit hot-path functions + fallback for cold paths
/// @dev Applies reentrancy and pause guards at the Router level before delegatecall to facets.
///      All state is stored in GridExStorage's diamond-namespaced slot.
contract GridExRouter {
    using GridOrder for GridOrder.GridState;

    error EnforcedPause();
    error FacetNotFound();

    /// @notice Initialize the Router with owner, vault, and initial admin facet
    /// @param _owner The address that will own this contract
    /// @param _vault The vault address for protocol fees
    /// @param _adminFacet The initial AdminFacet address (for bootstrapping selector registration)
    constructor(address _owner, address _vault, address _adminFacet) {
        if (_owner == address(0)) revert IProtocolErrors.InvalidAddress();
        if (_vault == address(0)) revert IProtocolErrors.InvalidAddress();

        GridExStorage.Layout storage l = GridExStorage.layout();
        l.owner = _owner;
        l.vault = _vault;
        l.nextPairId = 1;
        l.gridState.initialize();

        // Bootstrap: register AdminFacet's own selectors so the owner can call
        // setFacet / batchSetFacet through the fallback to register all other facets.
        // AdminFacet.setFacet.selector = 0x...
        // AdminFacet.batchSetFacet.selector = 0x...
        // We compute them from known signatures:
        l.selectorToFacet[bytes4(keccak256("setFacet(bytes4,address)"))] = _adminFacet;
        l.selectorToFacet[bytes4(keccak256("batchSetFacet(bytes4[],address[])"))] = _adminFacet;
        l.selectorToFacet[bytes4(keccak256("setWETH(address)"))] = _adminFacet;
        l.selectorToFacet[bytes4(keccak256("setQuoteToken(address,uint256)"))] = _adminFacet;
        l.selectorToFacet[bytes4(keccak256("setStrategyWhitelist(address,bool)"))] = _adminFacet;
        l.selectorToFacet[bytes4(keccak256("setOneshotProtocolFeeBps(uint32)"))] = _adminFacet;
        l.selectorToFacet[bytes4(keccak256("pause()"))] = _adminFacet;
        l.selectorToFacet[bytes4(keccak256("unpause()"))] = _adminFacet;
        l.selectorToFacet[bytes4(keccak256("rescueEth(address,uint256)"))] = _adminFacet;
        l.selectorToFacet[bytes4(keccak256("setFacetAllowlist(address,bool)"))] = _adminFacet;
        l.selectorToFacet[bytes4(keccak256("transferOwnership(address)"))] = _adminFacet;
    }

    /// @notice Allows the contract to receive ETH
    receive() external payable {}

    // ═══════════════════════════════════════════════════════════════════
    //  HOT-PATH: Place orders (pause check only)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Place grid orders with ERC20 tokens, delegated to TradeFacet
    function placeGridOrders(Currency, Currency, IGridOrder.GridOrderParam calldata) external {
        GridExStorage.Layout storage l = GridExStorage.layout();
        if (l.paused) revert EnforcedPause();
        _delegateToFacet(l);
    }

    /// @notice Place grid orders with ETH as either base or quote token
    // forge-lint: disable-next-line(mixed-case-function)
    function placeETHGridOrders(Currency, Currency, IGridOrder.GridOrderParam calldata) external payable {
        GridExStorage.Layout storage l = GridExStorage.layout();
        if (l.paused) revert EnforcedPause();
        _delegateToFacet(l);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  HOT-PATH: Fill orders (pause + reentrancy)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Fill a single ask grid order (buy base token)
    function fillAskOrder(uint256, uint128, uint128, bytes calldata, uint32) external payable {
        ReentrancyLib._enter();
        GridExStorage.Layout storage l = GridExStorage.layout();
        if (l.paused) revert EnforcedPause();
        _delegateToFacetGuarded(l);
    }

    /// @notice Fill multiple ask orders in a single transaction
    function fillAskOrders(uint64, uint256[] calldata, uint128[] calldata, uint128, uint128, bytes calldata, uint32)
        external
        payable
    {
        ReentrancyLib._enter();
        GridExStorage.Layout storage l = GridExStorage.layout();
        if (l.paused) revert EnforcedPause();
        _delegateToFacetGuarded(l);
    }

    /// @notice Fill a single bid grid order (sell base token)
    function fillBidOrder(uint256, uint128, uint128, bytes calldata, uint32) external payable {
        ReentrancyLib._enter();
        GridExStorage.Layout storage l = GridExStorage.layout();
        if (l.paused) revert EnforcedPause();
        _delegateToFacetGuarded(l);
    }

    /// @notice Fill multiple bid orders in a single transaction
    function fillBidOrders(uint64, uint256[] calldata, uint128[] calldata, uint128, uint128, bytes calldata, uint32)
        external
        payable
    {
        ReentrancyLib._enter();
        GridExStorage.Layout storage l = GridExStorage.layout();
        if (l.paused) revert EnforcedPause();
        _delegateToFacetGuarded(l);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  HOT-PATH: Cancel & withdraw (reentrancy only)
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Cancel an entire grid and withdraw all remaining tokens
    function cancelGrid(address, uint128, uint32) external {
        ReentrancyLib._enter();
        _delegateToFacetGuarded(GridExStorage.layout());
    }

    /// @notice Cancel a range of consecutive grid orders
    function cancelGridOrders(address, uint256, uint32, uint32) external {
        ReentrancyLib._enter();
        _delegateToFacetGuarded(GridExStorage.layout());
    }

    /// @notice Cancel specific orders within a grid by ID list
    function cancelGridOrders(uint128, address, uint256[] memory, uint32) external {
        ReentrancyLib._enter();
        _delegateToFacetGuarded(GridExStorage.layout());
    }

    /// @notice Withdraw accumulated profits from a grid
    function withdrawGridProfits(uint128, uint256, address, uint32) external {
        ReentrancyLib._enter();
        _delegateToFacetGuarded(GridExStorage.layout());
    }

    // ═══════════════════════════════════════════════════════════════════
    //  COLD-PATH: fallback routes view, admin, and misc selectors
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Routes unmatched selectors to the appropriate facet via delegatecall
    fallback() external payable {
        GridExStorage.Layout storage l = GridExStorage.layout();
        address facet = l.selectorToFacet[msg.sig];
        if (facet == address(0)) revert FacetNotFound();

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Internal delegatecall helpers
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Delegatecall to the facet mapped for msg.sig (no reentrancy guard cleanup)
    function _delegateToFacet(GridExStorage.Layout storage l) internal {
        address facet = l.selectorToFacet[msg.sig];
        if (facet == address(0)) revert FacetNotFound();

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// @dev Delegatecall to facet with reentrancy guard cleanup on success and revert
    function _delegateToFacetGuarded(GridExStorage.Layout storage l) internal {
        address facet = l.selectorToFacet[msg.sig];
        if (facet == address(0)) revert FacetNotFound();

        // Compute slot in Solidity so it matches ReentrancyLib exactly
        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 reentrancySlot = keccak256("gridex.reentrancy.guard");

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())

            // Always clear reentrancy guard (transient storage)
            tstore(reentrancySlot, 0)

            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
