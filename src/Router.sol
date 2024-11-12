// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./interfaces/IWETH.sol";
import "./interfaces/IGridEx.sol";
import "./interfaces/IGridExCallback.sol";
import {GridEx} from "./GridEx.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract Router is IGridExCallback {
    IGridEx public immutable gridEx;
    address public immutable WETH;
    address payer;

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
    ) public {
        payer = msg.sender;
        gridEx.placeGridOrders(msg.sender, base, quote, param);
    }

    function placeETHGridOrders(
        address base,
        address quote,
        GridEx.GridOrderParam calldata param
    ) public payable {
        payer = msg.sender;
        gridEx.placeGridOrders(msg.sender, base, quote, param);
    }

    function fillAskOrder(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) public payable {
        payer = msg.sender;
        gridEx.fillAskOrder(msg.sender, orderId, amt, minAmt);
    }

    /// @notice Fill multiple ask orders
    function fillAskOrders(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) public payable {
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

    function fillBidOrder(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) public payable {
        payer = msg.sender;
        gridEx.fillBidOrder(msg.sender, orderId, amt, minAmt);
    }

    function fillBidOrders(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) public payable {
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

    function gridExPlaceOrderCallback(address token, uint256 amount) public {
        transferToken(token, amount);
    }

    function gridExSwapCallback(address token, uint256 amount) public {
        transferToken(token, amount);
    }

    function transferToken(address token, uint256 amount) private {
        if (token == WETH) {
            IWETH(WETH).deposit{value: amount}();
            SafeTransferLib.safeTransferETH(msg.sender, amount);
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
