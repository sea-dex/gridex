// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "./IGridOrder.sol";
import "../libraries/Currency.sol";

interface IGridEx {
    /// @notice Emitted when a pair is created
    /// @param base The base token of the pair
    /// @param quote The quote token of the pair
    /// @param pairId The pair id
    // event PairCreated(Currency indexed base, Currency indexed quote, uint256 indexed pairId);

    /// @notice Emitted when quote token set
    /// @param quote The quote token
    /// @param priority The priority of the quote token
    event QuotableTokenUpdated(Currency quote, uint256 priority);

    /// @notice Emitted when withdraw grid profit
    /// @param gridId The grid order Id
    /// @param quote The quote token
    /// @param to The address receive quote token
    /// @param amt Amount
    event WithdrawProfit(
        uint96 gridId,
        Currency quote,
        address to,
        uint256 amt
    );

    /// Grid order param
    struct GridOrderParam {
        uint160 askPrice0;
        uint160 askGap;
        uint160 bidPrice0;
        uint160 bidGap;
        uint32 askOrderCount;
        uint32 bidOrderCount;
        uint32 fee; // bps
        bool compound;
        uint128 baseAmount;
    }

    /// @notice Place WETH grid orders, ether base or quote should be ETH
    /// @param base The base token
    /// @param quote The quote token
    function placeETHGridOrders(
        Currency base,
        Currency quote,
        GridOrderParam calldata param
    ) external payable;

    /// @notice Place grid orders
    /// @param base The base token
    /// @param quote The quote token
    function placeGridOrders(
        Currency base,
        Currency quote,
        GridOrderParam calldata param
    ) external;

    /// @notice Fill ask grid order
    /// @param orderId The grid order id
    /// @param amt The base amount of taker to buy
    /// @param minAmt The min base amount of taker to buy
    function fillAskOrder(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt, // base amount
        uint32 flag
    ) external payable;

    /// @notice Fill multiple ask orders
    function fillAskOrders(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt, // base amount
        uint32 flag
    ) external payable;

    /// @notice Fill bid grid order
    /// @param orderId The grid order id
    /// @param amt The base amt of taker to sell
    /// @param minAmt The min base amt of taker to sell
    function fillBidOrder(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt, // base amount
        uint32 flag
    ) external payable;

    /// @notice Fill multiple bid orders
    function fillBidOrders(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt, // base amount
        uint32 flag
    ) external payable;

    /// @notice Cancel grid orders
    /// @param gridId The grid id
    function cancelGridOrders(
        uint96 gridId,
        address recipient,
        uint96[] memory idList,
        uint32 flag
    ) external;

    /// @notice Cancel grid orders
    /// @param gridId The grid id
    function cancelGridOrders(
        uint96 gridId,
        address recipient,
        uint96 startOrderId,
        uint96 howmany,
        uint32 flag
    ) external;

    /// @notice set or update the quote token priority
    /// @dev Must be called by the current owner
    /// @param token The quotable token
    /// @param priority The priority of the quotable token
    function setQuoteToken(Currency token, uint256 priority) external;

    /// @notice Collect the protocol fee
    /// @param recipient The address to which collected protocol fees should be sent
    /// @param amount The maximum amount
    /// @param flag If profit is WETH, flag = 1 will receive ETH or else WETH
    function collectProtocolFee(
        Currency token,
        address recipient,
        uint256 amount,
        uint32 flag
    ) external;

    /// @notice withdraw grid profits
    /// @param gridId The grid order Id
    /// @param amt The amount to withdraw, 0 withdraw all profits
    /// @param to The address to receive
    /// @param flag If profit is WETH, flag = 1 will receive ETH or else WETH
    function withdrawGridProfits(
        uint64 gridId,
        uint256 amt,
        address to,
        uint32 flag
    ) external;

    /// @notice Get grid order info
    /// @param id The grid order Id by orderId
    function getGridOrder(
        uint96 id
    ) external view returns (IGridOrder.Order memory order);

    /// @notice Get multiple grid orders info by id list
    /// @param idList The orderId list
    function getGridOrders(
        uint96[] calldata idList
    ) external view returns (IGridOrder.Order[] memory);

    /// @notice Get grid order profits
    /// @param gridId The grid order Id
    function getGridProfits(uint96 gridId) external view returns (uint256);

    /// @notice get grid config info
    /// @param gridId The grid order Id
    function getGridConfig(
        uint96 gridId
    ) external returns (IGridOrder.GridConfig memory);
}
