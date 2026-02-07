// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

// forge-lint: disable-next-line(unaliased-plain-import)
import "./IGridOrder.sol";
// forge-lint: disable-next-line(unaliased-plain-import)
import "../libraries/Currency.sol";

interface IGridEx {
    /// @notice Emitted when quote token set
    /// @param quote The quote token
    /// @param priority The priority of the quote token
    event QuotableTokenUpdated(Currency quote, uint256 priority);

    /// @notice Emitted when withdraw grid profit
    /// @param gridId The grid order Id
    /// @param quote The quote token
    /// @param to The address receive quote token
    /// @param amt Amount
    event WithdrawProfit(uint128 gridId, Currency quote, address to, uint256 amt);

    /// @notice Place WETH grid orders, ether base or quote should be ETH
    /// @param base The base token
    /// @param quote The quote token
    // forge-lint: disable-next-line(mixed-case-function)
    function placeETHGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param)
        external
        payable;

    /// @notice Place grid orders
    /// @param base The base token
    /// @param quote The quote token
    /// @param param Parameters of the grid order to create
    function placeGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param) external;

    /// @notice Fill ask grid order
    /// @param gridOrderId The gridId and order id
    /// @param amt The base amount of taker to buy
    /// @param minAmt The min base amount of taker to buy
    /// @param data The callback params
    /// @param flag 0: both base and quote is NOT ETH; 1: inToken(quote) is ETH; 2: outToken(base) is ETH
    function fillAskOrder(
        uint256 gridOrderId,
        uint128 amt,
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    ) external payable;

    /// @notice Fill multiple ask orders
    function fillAskOrders(
        uint64 pairId,
        uint256[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    ) external payable;

    /// @notice Fill bid grid order
    /// @param gridOrderId The gridId and order id
    /// @param amt The base amt of taker to sell
    /// @param minAmt The min base amt of taker to sell
    /// @param flag 0: both base and quote is NOT ETH; 1: inToken(base) is ETH; 2: outToken(quote) is ETH
    function fillBidOrder(
        uint256 gridOrderId,
        uint128 amt,
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    ) external payable;

    /// @notice Fill multiple bid orders
    function fillBidOrders(
        uint64 pairId,
        uint256[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    ) external payable;

    /// @notice Cancel whole grid orders
    function cancelGrid(address recipient, uint128 gridId, uint32 flag) external;

    /// @notice Cancel some of grid orders
    /// @param gridId The grid id
    /// @param recipient The recieve address
    /// @param idList The grid order Id list to cancel
    /// @param flag: 0: both base and quote NOT ETH; 1: base is WETH and want ETH back; 2: quote is WETH and want ETH back
    function cancelGridOrders(uint128 gridId, address recipient, uint256[] memory idList, uint32 flag) external;

    /// @notice Cancel grid orders
    /// @param recipient The recieve address
    /// @param startGridOrderId The first grid Id + order Id to cancel
    /// @param howmany Order count to be canceled
    /// @param flag: 0: both base and quote NOT ETH; 1: base is WETH and want ETH back; 2: quote is WETH and want ETH back
    function cancelGridOrders(address recipient, uint256 startGridOrderId, uint32 howmany, uint32 flag) external;

    /// @notice set or update the quote token priority
    /// @dev Must be called by the current owner
    /// @param token The quotable token
    /// @param priority The priority of the quotable token
    function setQuoteToken(Currency token, uint256 priority) external;

    /// @notice Collect the protocol fee
    /// @param recipient The address to which collected protocol fees should be sent
    /// @param amount The maximum amount
    /// @param flag If profit is WETH, flag = 1 will receive ETH or else WETH
    // function collectProtocolFee(
    //     Currency token,
    //     address recipient,
    //     uint256 amount,
    //     uint32 flag
    // ) external;

    /// @notice withdraw grid profits
    /// @param gridId The grid order Id
    /// @param amt The amount to withdraw, 0 withdraw all profits
    /// @param to The address to receive
    /// @param flag If profit is WETH, flag = 1 will receive ETH or else WETH
    function withdrawGridProfits(uint128 gridId, uint256 amt, address to, uint32 flag) external;

    /// @notice Get grid order info
    /// @param id The grid order Id by orderId
    function getGridOrder(uint256 id) external view returns (IGridOrder.OrderInfo memory order);

    /// @notice Get multiple grid orders info by id list
    /// @param idList The orderId list
    function getGridOrders(uint256[] calldata idList) external view returns (IGridOrder.OrderInfo[] memory);

    /// @notice Get grid order profits
    /// @param gridId The grid order Id
    function getGridProfits(uint96 gridId) external view returns (uint256);

    /// @notice get grid config info
    /// @param gridId The grid order Id
    function getGridConfig(uint96 gridId) external returns (IGridOrder.GridConfig memory);
}
