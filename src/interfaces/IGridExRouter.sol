// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./IGridOrder.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../libraries/Currency.sol";

/// @title IGridExRouter
/// @author GridEx Protocol
/// @notice Interface for the GridExRouter: combined interface for all operations
interface IGridExRouter {
    /// @notice Emitted when a facet selector mapping is updated
    event FacetUpdated(bytes4 indexed selector, address indexed facet);

    /// @notice Emitted when a quote token's priority is set or updated
    event QuotableTokenUpdated(Currency quote, uint256 priority);

    /// @notice Emitted when grid profits are withdrawn
    event WithdrawProfit(uint48 gridId, Currency quote, address to, uint256 amt);

    /// @notice Get the facet address for a selector
    function facetAddress(bytes4 selector) external view returns (address);

    /// @notice Get the contract owner
    function owner() external view returns (address);

    /// @notice Get the vault address
    function vault() external view returns (address);

    /// @notice Get the WETH address
    function WETH() external view returns (address);

    /// @notice Check if the contract is paused
    function paused() external view returns (bool);

    /// @notice Get the current protocol fee for oneshot orders
    function getOneshotProtocolFeeBps() external view returns (uint32);

    /// @notice Check if a strategy is whitelisted
    function isStrategyWhitelisted(address strategy) external view returns (bool);

    /// @notice Get information about a single grid order
    function getGridOrder(uint64 id) external view returns (IGridOrder.OrderInfo memory order);

    /// @notice Get information about multiple grid orders
    function getGridOrders(uint64[] calldata idList) external view returns (IGridOrder.OrderInfo[] memory);

    /// @notice Get the accumulated profits for a grid
    function getGridProfits(uint48 gridId) external view returns (uint256);

    /// @notice Get the configuration for a grid
    function getGridConfig(uint48 gridId) external view returns (IGridOrder.GridConfig memory);

    /// @notice Get the pair ID for a token pair
    function getPairIdByTokens(Currency base, Currency quote) external view returns (uint64);

    /// @notice Get the tokens for a pair ID
    function getPairTokens(uint64 pairId) external view returns (Currency base, Currency quote);

    /// @notice Get pair info by pair ID
    function getPairById(uint64 pairId) external view returns (Currency base, Currency quote, uint64 id);

    // ═══════════════════════════════════════════════════════════════════
    //  TRADING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Place grid orders with ERC20 tokens
    function placeGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param) external;

    /// @notice Place grid orders with ETH as either base or quote token
    // forge-lint: disable-next-line(mixed-case-function)
    function placeETHGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param)
        external
        payable;

    /// @notice Fill a single ask grid order (buy base token)
    function fillAskOrder(uint64 gridOrderId, uint128 amt, uint128 minAmt, bytes calldata data, uint32 flag)
        external
        payable;

    /// @notice Fill multiple ask orders in a single transaction
    function fillAskOrders(
        uint64 pairId,
        uint64[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt,
        uint128 minAmt,
        bytes calldata data,
        uint32 flag
    ) external payable;

    /// @notice Fill a single bid grid order (sell base token)
    function fillBidOrder(uint64 gridOrderId, uint128 amt, uint128 minAmt, bytes calldata data, uint32 flag)
        external
        payable;

    /// @notice Fill multiple bid orders in a single transaction
    function fillBidOrders(
        uint64 pairId,
        uint64[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt,
        uint128 minAmt,
        bytes calldata data,
        uint32 flag
    ) external payable;

    // ═══════════════════════════════════════════════════════════════════
    //  CANCEL & WITHDRAW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Cancel an entire grid and withdraw all remaining tokens
    function cancelGrid(address recipient, uint48 gridId, uint32 flag) external;

    /// @notice Cancel specific orders within a grid
    function cancelGridOrders(uint48 gridId, address recipient, uint64[] memory idList, uint32 flag) external;

    /// @notice Cancel a range of consecutive grid orders
    function cancelGridOrders(address recipient, uint64 startGridOrderId, uint32 howmany, uint32 flag) external;

    /// @notice Withdraw accumulated profits from a grid
    function withdrawGridProfits(uint48 gridId, uint256 amt, address to, uint32 flag) external;

    /// @notice Modify the fee for a grid
    function modifyGridFee(uint48 gridId, uint32 fee) external;

    // ═══════════════════════════════════════════════════════════════════
    //  ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Set the WETH address
    // forge-lint: disable-next-line
    function setWETH(address _weth) external;

    /// @notice Set or update a token's quote priority
    function setQuoteToken(Currency token, uint256 priority) external;

    /// @notice Set the whitelist status for a strategy contract
    function setStrategyWhitelist(address strategy, bool whitelisted) external;

    /// @notice Set the protocol fee for oneshot orders
    function setOneshotProtocolFeeBps(uint32 feeBps) external;

    /// @notice Pause the contract
    function pause() external;

    /// @notice Unpause the contract
    function unpause() external;
}
