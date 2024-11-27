// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "./IGridEx.sol";

interface IRouter {
    function placeGridOrders(
        address base,
        address quote,
        IGridEx.GridOrderParam calldata param
    ) external;

    function placeETHGridOrders(
        address base,
        address quote,
        IGridEx.GridOrderParam calldata param
    ) external payable;

    function fillAskOrder(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) external;

    function fillAskOrderETH(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) external payable;

    function fillAskOrders(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) external;

    function fillAskOrdersETH(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) external payable;

    function fillBidOrder(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) external;

    function fillBidOrderETH(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) external payable;

    function fillBidOrders(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) external;

    function fillBidOrdersETH(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) external payable;
}
