// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./interfaces/IWETH.sol";
import "./interfaces/IGridEx.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IGridExCallback.sol";
import {GridEx} from "./GridEx.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract Router is IRouter, IGridExCallback {
    IGridEx public immutable gridEx;
    address public immutable WETH;
    address payer;
    uint ethPay = 1; // 1: not use ETH; 2: use ETH

    constructor(address _ex) {
        gridEx = IGridEx(_ex);
        WETH = gridEx.WETH();
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    function placeGridOrders(
        address base,
        address quote,
        GridEx.GridOrderParam calldata param
    ) external override {
        payer = msg.sender;
        gridEx.placeGridOrders(msg.sender, base, quote, param);
    }

    function placeETHGridOrders(
        address base,
        address quote,
        GridEx.GridOrderParam calldata param
    ) external override payable {
        payer = msg.sender;
        if (base == address(0)) {
            base = WETH;
        } else if (quote == address(0)) {
            quote = WETH;
        } else {
            revert('E');
        }
        IWETH(WETH).deposit{value: msg.value}();

        ethPay = 2;
        gridEx.placeGridOrders(msg.sender, base, quote, param);
        ethPay = 1;
    }

    /// @notice Fill one ask orders
    function fillAskOrder(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) external override {
        payer = msg.sender;
        gridEx.fillAskOrder(msg.sender, orderId, amt, minAmt);
    }

    /// @notice Fill one ask orders, base or quote is ETH
    function fillAskOrderETH(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) external override payable {
        payer = msg.sender;
        IWETH(WETH).deposit{value: msg.value}();

        ethPay = 2;
        gridEx.fillAskOrder(msg.sender, orderId, amt, minAmt);
        ethPay = 1;
    }

    /// @notice Fill multiple ask orders
    function fillAskOrders(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) external override {
        payer = msg.sender;
        gridEx.fillAskOrders(
            msg.sender,
            pairId,
            idList,
            amtList,
            maxAmt,
            minAmt
        );
    }

    /// @notice Fill multiple WETH ask orders, pay by ETH
    function fillAskOrdersETH(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) external override payable {
        payer = msg.sender;
        IWETH(WETH).deposit{value: msg.value}();
        ethPay = 2;
        gridEx.fillAskOrders(
            msg.sender,
            pairId,
            idList,
            amtList,
            maxAmt,
            minAmt
        );
        ethPay = 1;
    }

    function fillBidOrder(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) external override {
        payer = msg.sender;
        gridEx.fillBidOrder(msg.sender, orderId, amt, minAmt);
    }

    function fillBidOrderETH(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) external override payable {
        payer = msg.sender;
        IWETH(WETH).deposit{value: msg.value}();
        ethPay = 2;
        gridEx.fillBidOrder(msg.sender, orderId, amt, minAmt);
        ethPay = 1;
    }

    function fillBidOrders(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) external override {
        payer = msg.sender;
        gridEx.fillBidOrders(
            msg.sender,
            pairId,
            idList,
            amtList,
            maxAmt,
            minAmt
        );
    }

    function fillBidOrdersETH(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) external override payable {
        payer = msg.sender;
        IWETH(WETH).deposit{value: msg.value}();
        ethPay = 2;
        gridEx.fillBidOrders(
            msg.sender,
            pairId,
            idList,
            amtList,
            maxAmt,
            minAmt
        );
        ethPay = 1;
    }

    function gridExPlaceOrderCallback(address token, uint256 amount) external override {
        transferToken(token, amount);
    }

    function gridExSwapCallback(address token, uint256 amount) external override {
        transferToken(token, amount);
    }

    function transferToken(address token, uint256 amount) private {
        if (ethPay == 2 && token == address(WETH)) {
            SafeTransferLib.safeTransfer(ERC20(token), msg.sender, amount);
        } else {
            SafeTransferLib.safeTransferFrom(
                ERC20(token),
                payer,
                msg.sender,
                amount
            );
        }
    }
}
