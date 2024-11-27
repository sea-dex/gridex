// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "../libraries/Currency.sol";

interface IGridEx {
    /// @notice Emitted when a pair is created
    /// @param base The base token of the pair
    /// @param quote The quote token of the pair
    /// @param pairId The pair id
    event PairCreated(
        Currency indexed base,
        Currency indexed quote,
        uint256 indexed pairId
    );

    /// @notice Emitted when quote token set
    /// @param quote The quote token
    /// @param priority The priority of the quote token
    event QuotableTokenUpdated(
        Currency quote,
        uint priority
    );

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

    /// @notice WETH address
    function WETH() external returns (address);
    
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

    /// @notice Place grid orders
    /// @param maker The maker address
    /// @param base The base token
    /// @param quote The quote token
    function placeGridOrders(
        address maker,
        Currency base,
        Currency quote,
        GridOrderParam calldata param
    ) external;

    /// @notice Fill ask grid order
    /// @param taker The taker address
    /// @param orderId The grid order id
    /// @param amt The base amount of taker to buy
    /// @param minAmt The min base amount of taker to buy
    function fillAskOrder(
        address taker,
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) external;

    /// @notice Fill multiple ask orders
    function fillAskOrders(
        address taker,
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) external;

    /// @notice Fill bid grid order
    /// @param taker The taker address
    /// @param orderId The grid order id
    /// @param amt The base amt of taker to sell
    /// @param minAmt The min base amt of taker to sell
    function fillBidOrder(
        address taker,
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) external;

    /// @notice Fill multiple bid orders
    function fillBidOrders(
        address taker,
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) external;

    /// @notice Cancel grid orders
    /// @param pairId The pair id
    function cancelGridOrders(uint64 pairId, address recipient, uint64[] calldata idList) external;

    /// @notice set or update the quote token priority
    /// @dev Must be called by the current owner
    /// @param token The quotable token
    /// @param priority The priority of the quotable token
    function setQuoteToken(Currency token, uint priority) external;
    
    /// @notice Collect the protocol fee
    /// @param recipient The address to which collected protocol fees should be sent
    /// @param amount The maximum amount
    function collectProtocolFee(
        Currency token,
        address recipient,
        uint256 amount
    ) external;

    /// @notice withdraw grif profits
    /// @param gridId The grid order Id
    /// @param amt The amount to withdraw, 0 withdraw all profits
    /// @param to The address to receive
    function withdrawGridProfits(uint64 gridId, uint256 amt, address to) external;
}
