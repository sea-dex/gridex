// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./IGridOrder.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "./IPair.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../libraries/Currency.sol";

/// @title IGridEx
/// @author GridEx Protocol
/// @notice Interface for the main GridEx decentralized grid trading protocol
/// @dev Defines all external functions for grid order management and trading
interface IGridEx {
    /// @notice Emitted when a quote token's priority is set or updated
    /// @param quote The quote token address
    /// @param priority The priority value (higher = more preferred as quote)
    event QuotableTokenUpdated(Currency quote, uint256 priority);

    /// @notice Emitted when grid profits are withdrawn
    /// @param gridId The grid order ID
    /// @param quote The quote token address
    /// @param to The recipient address
    /// @param amt The amount withdrawn
    event WithdrawProfit(uint128 gridId, Currency quote, address to, uint256 amt);

    /// @notice Place grid orders with ETH as either base or quote token
    /// @dev Either base or quote must be address(0) representing ETH
    /// @param base The base token (address(0) for ETH)
    /// @param quote The quote token (address(0) for ETH)
    /// @param param The grid order parameters
    // forge-lint: disable-next-line(mixed-case-function)
    function placeETHGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param)
        external
        payable;

    /// @notice Place grid orders with ERC20 tokens
    /// @dev Neither base nor quote can be address(0)
    /// @param base The base token address
    /// @param quote The quote token address
    /// @param param The grid order parameters including prices, amounts, and fees
    function placeGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param) external;

    /// @notice Fill a single ask grid order (buy base token)
    /// @dev Taker pays quote token and receives base token
    /// @param gridOrderId The combined grid ID and order ID
    /// @param amt The base amount to buy
    /// @param minAmt The minimum base amount to accept (slippage protection)
    /// @param data Callback data (if non-empty, triggers flash-swap callback)
    /// @param flag Bit flags: 0 = ERC20 only, 1 = quote is ETH, 2 = base is ETH
    function fillAskOrder(
        uint256 gridOrderId,
        uint128 amt,
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    )
        external
        payable;

    /// @notice Fill multiple ask orders in a single transaction
    /// @dev More gas efficient than multiple single fills
    /// @param pairId The trading pair ID
    /// @param idList Array of grid order IDs to fill
    /// @param amtList Array of base amounts to fill for each order
    /// @param maxAmt Maximum total base amount to buy
    /// @param minAmt Minimum total base amount to accept
    /// @param data Callback data for flash-swap
    /// @param flag Bit flags for ETH handling
    function fillAskOrders(
        uint64 pairId,
        uint256[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    ) external payable;

    /// @notice Fill a single bid grid order (sell base token)
    /// @dev Taker pays base token and receives quote token
    /// @param gridOrderId The combined grid ID and order ID
    /// @param amt The base amount to sell
    /// @param minAmt The minimum base amount to accept (slippage protection)
    /// @param data Callback data (if non-empty, triggers flash-swap callback)
    /// @param flag Bit flags: 0 = ERC20 only, 1 = base is ETH, 2 = quote is ETH
    function fillBidOrder(
        uint256 gridOrderId,
        uint128 amt,
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    )
        external
        payable;

    /// @notice Fill multiple bid orders in a single transaction
    /// @dev More gas efficient than multiple single fills
    /// @param pairId The trading pair ID
    /// @param idList Array of grid order IDs to fill
    /// @param amtList Array of base amounts to fill for each order
    /// @param maxAmt Maximum total base amount to sell
    /// @param minAmt Minimum total base amount to accept
    /// @param data Callback data for flash-swap
    /// @param flag Bit flags for ETH handling
    function fillBidOrders(
        uint64 pairId,
        uint256[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    ) external payable;

    /// @notice Cancel an entire grid and withdraw all remaining tokens
    /// @param recipient The address to receive the withdrawn tokens
    /// @param gridId The grid ID to cancel
    /// @param flag Bit flags: 1 = base to ETH, 2 = quote to ETH
    function cancelGrid(address recipient, uint128 gridId, uint32 flag) external;

    /// @notice Cancel specific orders within a grid
    /// @param gridId The grid ID containing the orders
    /// @param recipient The address to receive the withdrawn tokens
    /// @param idList Array of order IDs to cancel
    /// @param flag Bit flags: 1 = base to ETH, 2 = quote to ETH
    function cancelGridOrders(uint128 gridId, address recipient, uint256[] memory idList, uint32 flag) external;

    /// @notice Cancel a range of consecutive grid orders
    /// @param recipient The address to receive the withdrawn tokens
    /// @param startGridOrderId The first grid order ID to cancel
    /// @param howmany The number of consecutive orders to cancel
    /// @param flag Bit flags: 1 = base to ETH, 2 = quote to ETH
    function cancelGridOrders(address recipient, uint256 startGridOrderId, uint32 howmany, uint32 flag) external;

    /// @notice Set the WETH address
    /// @dev Only callable by the contract owner. Called after deployment to configure
    ///      chain-specific WETH address without affecting deterministic proxy addresses.
    /// @param _weth The WETH contract address on this chain
    // forge-lint: disable-next-line
    function setWETH(address _weth) external;

    /// @notice Set or update a token's quote priority
    /// @dev Only callable by the contract owner
    /// @param token The token address to configure
    /// @param priority The priority value (0 = not quotable, higher = more preferred)
    function setQuoteToken(Currency token, uint256 priority) external;

    /// @notice Modify the fee for a grid
    /// @dev Only callable by the grid owner
    /// @param gridId The grid ID to modify
    /// @param fee The new fee in basis points (must be between MIN_FEE and MAX_FEE)
    function modifyGridFee(uint128 gridId, uint32 fee) external;

    /// @notice Withdraw accumulated profits from a grid
    /// @param gridId The grid ID to withdraw profits from
    /// @param amt The amount to withdraw (0 = withdraw all)
    /// @param to The recipient address
    /// @param flag If quote is WETH and flag = 1, receive ETH instead
    function withdrawGridProfits(uint128 gridId, uint256 amt, address to, uint32 flag) external;

    /// @notice Get information about a single grid order
    /// @param id The grid order ID
    /// @return order The order information struct
    function getGridOrder(uint256 id) external view returns (IGridOrder.OrderInfo memory order);

    /// @notice Get information about multiple grid orders
    /// @param idList Array of grid order IDs to query
    /// @return Array of order information structs
    function getGridOrders(uint256[] calldata idList) external view returns (IGridOrder.OrderInfo[] memory);

    /// @notice Get the accumulated profits for a grid
    /// @param gridId The grid ID to query
    /// @return The profit amount in quote tokens
    function getGridProfits(uint96 gridId) external view returns (uint256);

    /// @notice Get the configuration for a grid
    /// @param gridId The grid ID to query
    /// @return The grid configuration struct
    function getGridConfig(uint96 gridId) external returns (IGridOrder.GridConfig memory);

    /// @notice Set the protocol fee for oneshot orders
    /// @dev Only callable by the owner. For oneshot orders, all fee goes to protocol (no LP fee).
    /// @param feeBps The new fee in basis points (must be between MIN_FEE and MAX_FEE)
    function setOneshotProtocolFeeBps(uint32 feeBps) external;

    /// @notice Get the current protocol fee for oneshot orders
    /// @return The oneshot protocol fee in basis points
    function getOneshotProtocolFeeBps() external view returns (uint32);

    /// @notice Set the whitelist status for a strategy contract
    /// @dev Only callable by the owner. Only whitelisted strategies can be used for grid orders.
    /// @param strategy The strategy contract address
    /// @param whitelisted True to whitelist, false to remove from whitelist
    function setStrategyWhitelist(address strategy, bool whitelisted) external;

    /// @notice Check if a strategy is whitelisted
    /// @param strategy The strategy contract address to check
    /// @return True if the strategy is whitelisted
    function isStrategyWhitelisted(address strategy) external view returns (bool);

    /// @notice Get the contract owner
    /// @return The owner address
    function owner() external view returns (address);

    /// @notice Pause the contract
    function pause() external;

    /// @notice Unpause the contract
    function unpause() external;

    /// @notice Get the pair ID for a token pair
    /// @param base The base token
    /// @param quote The quote token
    /// @return The pair ID (0 if not exists)
    function getPairIdByTokens(Currency base, Currency quote) external view returns (uint64);

    /// @notice Get the tokens for a pair ID
    /// @param pairId The pair ID
    /// @return base The base token
    /// @return quote The quote token
    function getPairTokens(uint64 pairId) external view returns (Currency base, Currency quote);

    /// @notice Check if the contract is paused
    /// @return True if paused
    function paused() external view returns (bool);

    /// @notice Get the vault address
    /// @return The vault address
    function vault() external view returns (address);

    /// @notice Get the WETH address
    /// @return The WETH address
    function WETH() external view returns (address);

    /// @notice Get pair info by pair ID
    /// @param pairId The pair ID
    /// @return base The base token
    /// @return quote The quote token
    /// @return id The pair ID
    function getPairById(uint64 pairId) external view returns (Currency base, Currency quote, uint64 id);
}
