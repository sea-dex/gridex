// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./interfaces/IWETH.sol";
import "./interfaces/IPair.sol";
import "./interfaces/IGridEx.sol";
import "./interfaces/IGridExCallback.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPairDeployer.sol";
import "./interfaces/IERC20Minimal.sol";

import {Pair} from "./Pair.sol";
import {GridOrder} from "./GridOrder.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract GridEx is IGridEx, GridOrder, Pair, Owned, ReentrancyGuard {
    using SafeCast for *;
    using CurrencyLibrary for Currency;
    // using TransferHelper for IERC20Minimal;

    address public immutable WETH;

    mapping(uint96 orderId => Order) public bidOrders;
    mapping(uint96 orderId => Order) public askOrders;
    mapping(address => uint) public protocolFees;

    uint96 public nextGridId = 1;
    mapping(uint96 gridId => GridConfig) public gridConfigs;

    constructor(address weth_, address usd_) Owned(msg.sender) {
        // usd is the most priority quote token
        quotableTokens[usd_] = 1 << 20;
        quotableTokens[weth_] = 1 << 10;
        WETH = weth_;
    }

    function createGridConfig(
        address maker,
        uint64 pairId,
        uint32 orderCount,
        uint32 fee,
        bool compound,
        uint128 baseAmt
    ) private returns (uint96) {
        uint96 gridId = nextGridId++;

        gridConfigs[gridId] = GridConfig({
            owner: maker,
            profits: 0,
            baseAmt: baseAmt,
            pairId: pairId,
            orderCount: orderCount,
            fee: fee,
            compound: compound
        });
        return gridId;
    }

    /// place both side grid orders
    function placeGridOrders(
        address maker,
        address base,
        address quote,
        GridOrderParam calldata param
    ) public override nonReentrant {
        Pair memory pair = getOrCreatePair(base, quote);
        uint96 gridId = createGridConfig(
            maker,
            pair.pairId,
            param.askOrderCount + param.bidOrderCount,
            param.fee,
            param.compound,
            param.baseAmount
        );

        (
            uint96 startAskOrderId,
            uint128 baseAmt,
            uint96 startBidOrderId,
            uint128 quoteAmt
        ) = placeGridOrder(gridId, param, askOrders, bidOrders);
        // transfer base token
        if (baseAmt > 0) {
            uint256 balanceBefore = _balance(pair.base);
            IGridExCallback(msg.sender).gridExPlaceOrderCallback(
                pair.base,
                baseAmt
            );
            require(balanceBefore + baseAmt <= _balance(pair.base), "G1");
        }

        // transfer quote token
        if (quoteAmt > 0) {
            uint256 balanceBefore = _balance(pair.quote);
            IGridExCallback(msg.sender).gridExPlaceOrderCallback(
                pair.quote,
                quoteAmt
            );
            require(balanceBefore + quoteAmt <= _balance(pair.quote), "G2");
        }

        emit GridOrderCreated(
            maker,
            param.askPrice0,
            param.askGap,
            param.bidPrice0,
            param.bidGap,
            param.baseAmount,
            param.askOrderCount,
            param.bidOrderCount,
            gridId,
            param.compound,
            startAskOrderId,
            startBidOrderId
        );
    }

    /// @dev Get the pool's balance of token
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    function _balance(address token) private view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(
                IERC20Minimal.balanceOf.selector,
                address(this)
            )
        );
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    // taker is BUY
    function fillAskOrder(
        address taker,
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) public override nonReentrant {
        bool isAsk = isAskGridOrder(orderId);
        Order storage order = isAsk ? askOrders[orderId] : bidOrders[orderId];
        GridConfig storage gridConfig = gridConfigs[order.gridId];
        (
            uint256 filledAmt,
            uint256 filledVol,
            uint256 protocolFee
        ) = _fillAskOrder(isAsk, amt, taker, order, gridConfig);

        if (minAmt > 0 && filledAmt < minAmt) {
            revert NotEnoughToFill();
        }

        Pair memory pair = getPairById[gridConfig.pairId];
        // transfer base token to taker
        SafeTransferLib.safeTransfer(ERC20(pair.base), taker, filledAmt);
        // protocol fee
        protocolFees[pair.quote] += protocolFee;

        // ensure receive enough quote token
        uint256 balanceBefore = _balance(pair.quote);
        IGridExCallback(msg.sender).gridExSwapCallback(pair.quote, filledVol);
        require(balanceBefore + filledVol <= _balance(pair.quote), "G3");
    }

    struct AccFilled {
        uint256 amt; // base amount
        uint256 vol; // quote amount
        uint256 fee; // protocol fee
    }

    // taker is BUY
    function fillAskOrders(
        address taker,
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) public override nonReentrant {
        if (idList.length != amtList.length) {
            revert InvalidParam();
        }

        AccFilled memory filled;
        for (uint i = 0; i < idList.length; ++i) {
            uint96 orderId = idList[i];
            uint128 amt = amtList[i];

            if (maxAmt > 0 && maxAmt < filled.amt + amt) {
                amt = maxAmt - uint128(filled.amt);
            }

            bool isAsk = isAskGridOrder(orderId);
            Order storage order = isAsk
                ? askOrders[orderId]
                : bidOrders[orderId];
            GridConfig storage gridConfig = gridConfigs[order.gridId];
            require(gridConfig.pairId == pairId, "G4");

            (
                uint256 filledBaseAmt,
                uint256 filledQuoteAmtWithFee,
                uint256 fee
            ) = _fillAskOrder(isAsk, amt, taker, order, gridConfig);

            unchecked {
                filled.amt += filledBaseAmt;
                filled.vol += filledQuoteAmtWithFee;
                filled.fee += fee;
            }

            if (maxAmt > 0 && filled.amt >= maxAmt) {
                break;
            }
        }

        if (minAmt > 0 && filled.amt < minAmt) {
            revert NotEnoughToFill();
        }

        Pair memory pair = getPairById[pairId];
        address quote = pair.quote;
        // transfer base token to taker
        SafeTransferLib.safeTransfer(ERC20(pair.base), taker, filled.amt);
        // protocol fee
        protocolFees[quote] += filled.fee;

        // ensure receive enough quote token
        uint256 balanceBefore = _balance(quote);
        IGridExCallback(msg.sender).gridExSwapCallback(quote, filled.vol);
        require(balanceBefore + filled.vol <= _balance(quote), "G5");
    }

    // taker is sell, amtList, maxAmt, minAmt is base token amount
    function fillBidOrder(
        address taker,
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) public override nonReentrant {
        bool isAsk = isAskGridOrder(orderId);
        Order storage order = isAsk ? askOrders[orderId] : bidOrders[orderId];
        GridConfig storage gridConfig = gridConfigs[order.gridId];
        (
            uint256 filledAmt,
            uint256 filledVol,
            uint256 protocolFee
        ) = _fillBidOrder(isAsk, amt, taker, order, gridConfig);

        if (minAmt > 0 && filledAmt < minAmt) {
            revert NotEnoughToFill();
        }

        Pair memory pair = getPairById[gridConfig.pairId];
        // transfer quote token to taker
        SafeTransferLib.safeTransfer(ERC20(pair.quote), taker, filledVol);
        // protocol fee
        protocolFees[pair.quote] += protocolFee;

        // ensure receive enough base token
        uint256 balanceBefore = _balance(pair.base);
        IGridExCallback(msg.sender).gridExSwapCallback(pair.base, filledAmt);
        require(balanceBefore + filledAmt <= _balance(pair.base), "G6");
    }

    // taker is sell, amtList, maxAmt, minAmt is base token amount
    function fillBidOrders(
        address taker,
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) public override nonReentrant {
        if (idList.length != amtList.length) {
            revert InvalidParam();
        }

        uint256 filledAmt = 0; // accumulate base amount
        uint256 filledVol = 0; // accumulate quote amount
        uint256 protocolFee = 0;

        for (uint i = 0; i < idList.length; ++i) {
            uint96 orderId = idList[i];
            uint128 amt = amtList[i];

            if (maxAmt > 0 && maxAmt - filledAmt < amt) {
                amt = maxAmt - uint128(filledAmt);
            }

            bool isAsk = isAskGridOrder(orderId);
            Order storage order = isAsk
                ? askOrders[orderId]
                : bidOrders[orderId];
            GridConfig storage gridConfig = gridConfigs[order.gridId];
            require(gridConfig.pairId == pairId, "G7");
            (
                uint256 filledBaseAmt,
                uint256 filledQuoteAmtSubFee,
                uint256 fee
            ) = _fillBidOrder(isAsk, amt, taker, order, gridConfig);

            unchecked {
                filledAmt += filledBaseAmt;
                filledVol += filledQuoteAmtSubFee;
                protocolFee += fee;
            }

            if (maxAmt > 0 && filledAmt >= maxAmt) {
                break;
            }
        }

        if (minAmt > 0 && filledAmt < minAmt) {
            revert NotEnoughToFill();
        }

        Pair memory pair = getPairById[pairId];
        // transfer quote token to taker
        SafeTransferLib.safeTransfer(ERC20(pair.quote), taker, filledVol);
        // protocol fee
        protocolFees[pair.quote] += protocolFee;

        // ensure receive enough base token
        uint256 balanceBefore = _balance(pair.base);
        IGridExCallback(msg.sender).gridExSwapCallback(pair.base, filledAmt);
        require(balanceBefore + filledAmt <= _balance(pair.base), "G8");
    }

    function getGridOrder(uint96 id) public view returns (Order memory order) {
        if (isAskGridOrder(id)) {
            order = askOrders[id];
        } else {
            order = bidOrders[id];
        }
    }

    function getGridOrders(
        uint96[] calldata idList
    ) public view returns (Order[] memory) {
        Order[] memory orderList = new Order[](idList.length);

        for (uint i = 0; i < idList.length; i++) {
            uint96 id = idList[i];
            if (isAskGridOrder(idList[i])) {
                orderList[i] = askOrders[id];
            } else {
                orderList[i] = bidOrders[id];
            }
        }
        return orderList;
    }

    function getGridProfits(uint96 gridId) public view returns (uint256) {
        return gridConfigs[gridId].profits;
    }

    function getGridConfig(
        uint96 gridId
    ) public view returns (GridConfig memory) {
        return gridConfigs[gridId];
    }

    function withdrawGridProfits(
        uint64 gridId,
        uint256 amt,
        address to
    ) public override {
        GridConfig memory conf = gridConfigs[gridId];
        require(conf.owner == msg.sender);

        if (amt == 0) {
            amt = conf.profits;
        } else if (conf.profits < amt) {
            amt = conf.profits;
        }

        Pair memory pair = getPairById[conf.pairId];
        gridConfigs[gridId].profits = conf.profits - uint128(amt);
        SafeTransferLib.safeTransfer(ERC20(pair.quote), to, amt);

        emit WithdrawProfit(gridId, pair.quote, to, amt);
    }

    // cancel grid order will cancel both ask order and bid order
    function cancelGridOrders(
        uint64 pairId,
        address recipient,
        uint64[] calldata idList
    ) public override {
        uint256 baseAmt = 0;
        uint256 quoteAmt = 0;
        uint256 totalBaseAmt = 0;
        uint256 totalQuoteAmt = 0;

        for (uint i = 0; i < idList.length; ) {
            uint64 id = idList[i];
            Order memory order;
            bool isAsk = isAskGridOrder(id);

            if (isAsk) {
                order = askOrders[id];
                baseAmt = order.amount;
                quoteAmt = order.revAmount;
            } else {
                order = bidOrders[id];
                baseAmt = order.revAmount;
                quoteAmt = order.amount;
            }
            uint96 gridId = order.gridId;
            GridConfig memory conf = gridConfigs[gridId];
            require(conf.pairId == pairId, "G9");
            if (msg.sender != conf.owner) {
                revert NotGridOrder();
            }

            emit CancelGridOrder(msg.sender, id, gridId, baseAmt, quoteAmt);

            if (isAsk) {
                delete askOrders[id];
            } else {
                delete bidOrders[id];
            }

            unchecked {
                ++i;
                --conf.orderCount;
                totalBaseAmt += baseAmt;
                totalQuoteAmt += quoteAmt;
            }
            if (conf.orderCount == 0) {
                delete gridConfigs[gridId];
            }
        }

        Pair memory pair = getPairById[pairId];
        if (baseAmt > 0) {
            // transfer base
            transferToken(pair.base, recipient, totalBaseAmt);
        }
        if (quoteAmt > 0) {
            // transfer
            transferToken(pair.quote, recipient, totalQuoteAmt);
        }
    }

    function transferToken(address token, address to, uint256 amt) private {
        if (token == WETH) {
            IWETH(WETH).withdraw(amt);
            SafeTransferLib.safeTransferETH(to, amt);
        } else {
            SafeTransferLib.safeTransfer(ERC20(token), to, amt);
        }
    }

    /// @inheritdoc IGridEx
    function setQuoteToken(
        address token,
        uint priority
    ) external override onlyOwner {
        quotableTokens[token] = priority;

        emit QuotableTokenUpdated(token, priority);
    }

    /// @inheritdoc IGridEx
    function collectProtocolFee(
        address token,
        address recipient,
        uint256 amount
    ) external override onlyOwner {
        if (amount == 0) {
            amount = protocolFees[token] - 1;
        } else {
            amount = amount >= protocolFees[token]
                ? protocolFees[token] - 1
                : amount;
        }

        transferToken(token, recipient, amount);
    }
}
