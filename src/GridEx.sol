// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// import "./interfaces/IWETH.sol";
import {IPair} from "./interfaces/IPair.sol";
import {IGridOrder} from "./interfaces/IGridOrder.sol";
import {IGridEx} from "./interfaces/IGridEx.sol";
import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {IGridCallback} from "./interfaces/IGridCallback.sol";

import {AssetSettle} from "./AssetSettle.sol";
import {Pair} from "./Pair.sol";
import {GridOrder} from "./GridOrder.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

contract GridEx is
    IGridEx,
    AssetSettle,
    GridOrder,
    Pair,
    Owned,
    ReentrancyGuard
{
    using SafeCast for *;
    using CurrencyLibrary for Currency;

    mapping(Currency => uint256) public protocolFees;

    constructor(address weth_, address usd_) Owned(msg.sender) {
        // usd is the most priority quote token
        quotableTokens[Currency.wrap(usd_)] = 1 << 20;
        // quotableTokens[Currency.wrap(address(0))] = 1 << 19;
        quotableTokens[Currency.wrap(weth_)] = 1 << 19;
        WETH = weth_;
    }

    function placeETHGridOrders(
        Currency base,
        Currency quote,
        IGridOrder.GridOrderParam calldata param
    ) public payable {
        bool baseIsETH = false;
        if (base.isAddressZero()) {
            baseIsETH = true;
            base = Currency.wrap(WETH);
        } else if (quote.isAddressZero()) {
            quote = Currency.wrap(WETH);
        } else {
            revert InvalidParam();
        }

        (, uint128 baseAmt, uint128 quoteAmt) = _placeGridOrders(
            msg.sender,
            base,
            quote,
            param
        );

        if (baseIsETH) {
            _transferETHFrom(msg.sender, baseAmt, uint128(msg.value));
            _transferTokenFrom(quote, msg.sender, quoteAmt);
        } else {
            _transferETHFrom(msg.sender, quoteAmt, uint128(msg.value));
            _transferTokenFrom(base, msg.sender, baseAmt);
        }
    }

    /// @inheritdoc IGridEx
    function placeGridOrders(
        Currency base,
        Currency quote,
        IGridOrder.GridOrderParam calldata param
    ) public override {
        if (base.isAddressZero() || quote.isAddressZero()) {
            revert InvalidParam();
        }

        (
            Pair memory pair,
            uint128 baseAmt,
            uint128 quoteAmt
        ) = _placeGridOrders(msg.sender, base, quote, param);

        // transfer base token
        if (baseAmt > 0) {
            _transferTokenFrom(pair.base, msg.sender, baseAmt);
        }

        // transfer quote token
        if (quoteAmt > 0) {
            _transferTokenFrom(pair.quote, msg.sender, quoteAmt);
        }
    }

    function _placeGridOrders(
        address maker,
        Currency base,
        Currency quote,
        IGridOrder.GridOrderParam calldata param
    ) private returns (Pair memory pair, uint128 baseAmt, uint128 quoteAmt) {
        pair = getOrCreatePair(base, quote);
        (
            uint128 gridId,
            IGridOrder.GridConfig storage gridConf
        ) = _createGridConfig(maker, pair.pairId, param);

        uint128 startAskOrderId;
        uint128 startBidOrderId;
        (startAskOrderId, baseAmt, startBidOrderId, quoteAmt) = placeGridOrder(
            gridId,
            param
        );

        gridConf.startAskOrderId = startAskOrderId;
        gridConf.startBidOrderId = startBidOrderId;

        emit GridOrderCreated(
            msg.sender,
            pair.pairId,
            // param.askPrice0,
            // param.askGap,
            // param.bidPrice0,
            // param.bidGap,
            param.baseAmount,
            gridId,
            startAskOrderId,
            startBidOrderId,
            param.askOrderCount,
            param.bidOrderCount,
            param.fee,
            param.compound
        );
    }

    /// @inheritdoc IGridEx
    function fillAskOrder(
        uint256 gridOrderId,
        uint128 amt, // base amount
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    ) public payable override nonReentrant {
        // bool isAsk = isAskGridOrder(gridOrderId);
        // (uint128 gridId, uint128 orderId) = extractGridIdOrderId(gridOrderId);
        address taker = msg.sender;
        IGridOrder.OrderInfo memory orderInfo = getOrderInfo(gridOrderId, true);

        IGridOrder.OrderFillResult memory result = _fillAskOrder(
            amt,
            taker,
            orderInfo
        );

        if (minAmt > 0 && result.filledAmt < minAmt) {
            revert NotEnoughToFill();
        }

        IGridOrder.Order storage order = orderInfo.isAsk
            ? askOrders[orderInfo.orderId]
            : bidOrders[orderInfo.orderId];
        order.amount = result.orderAmt;
        order.revAmount = result.orderRevAmt;

        if (result.profit > 0) {
            // uint128 gridId = orderInfo.gridId;
            // IGridOrder.GridConfig storage gridConfig = gridConfigs[gridId];
            gridConfigs[orderInfo.gridId].profits += uint128(result.profit);
        }

        Pair memory pair = getPairById[orderInfo.pairId];
        // transfer base token to taker
        // pair.base.transfer(taker, filledAmt);
        // SafeTransferLib.safeTransfer(ERC20(pair.base), taker, filledAmt);
        // protocol fee
        protocolFees[pair.quote] += result.protocolFee;

        // ensure receive enough quote token
        // _settle(pair.quote, taker, filledVol, msg.value);

        uint128 inAmt = result.filledVol + result.lpFee + result.protocolFee;
        if (data.length > 0) {
            // always transfer ERC20 to msg.sender
            pair.base.transfer(msg.sender, result.filledAmt);
            uint256 balanceBefore = pair.quote.balanceOfSelf();
            IGridCallback(msg.sender).gridFillCallback(
                Currency.unwrap(pair.quote),
                Currency.unwrap(pair.base),
                inAmt,
                result.filledAmt,
                data
            );
            require(balanceBefore + inAmt <= pair.quote.balanceOfSelf(), "G1");
        } else {
            _settleAssetWith(
                pair.quote,
                pair.base,
                msg.sender,
                inAmt,
                result.filledAmt,
                msg.value,
                flag
            );
        }
    }

    struct AccFilled {
        uint128 amt; // base amount
        uint128 vol; // quote amount
        uint128 protocolFee; // protocol fee
    }

    /// @inheritdoc IGridEx
    function fillAskOrders(
        uint64 pairId,
        uint256[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    ) public payable override nonReentrant {
        if (idList.length != amtList.length) {
            revert InvalidParam();
        }

        address taker = msg.sender;
        AccFilled memory filled;
        for (uint256 i = 0; i < idList.length; ++i) {
            IGridOrder.OrderInfo memory orderInfo = getOrderInfo(
                idList[i],
                true
            );
            require(orderInfo.pairId == pairId, "G2");

            // uint96 orderId = idList[i];
            uint128 amt = amtList[i];

            if (maxAmt > 0 && maxAmt < filled.amt + amt) {
                amt = maxAmt - filled.amt;
            }

            // bool isAsk = isAskGridOrder(orderId);
            // IGridOrder.Order storage order = isAsk
            //     ? askOrders[orderId]
            //     : bidOrders[orderId];
            // IGridOrder.GridConfig storage gridConfig = gridConfigs[
            //     order.gridId
            // ];

            IGridOrder.OrderFillResult memory result = _fillAskOrder(
                amt,
                taker,
                orderInfo
            );

            IGridOrder.Order storage order = orderInfo.isAsk
                ? askOrders[orderInfo.orderId]
                : bidOrders[orderInfo.orderId];
            order.amount = result.orderAmt;
            order.revAmount = result.orderRevAmt;

            if (result.profit > 0) {
                // uint128 gridId = orderInfo.gridId;
                // IGridOrder.GridConfig storage gridConfig = gridConfigs[orderInfo.gridId];
                gridConfigs[orderInfo.gridId].profits += uint128(result.profit);
            }

            filled.amt += result.filledAmt;
            filled.vol += result.filledVol + result.lpFee + result.protocolFee;
            filled.protocolFee += result.protocolFee;

            if (maxAmt > 0 && filled.amt >= maxAmt) {
                break;
            }
        }

        if (minAmt > 0 && filled.amt < minAmt) {
            revert NotEnoughToFill();
        }

        Pair memory pair = getPairById[pairId];
        Currency quote = pair.quote;
        // transfer base token to taker
        // pair.base.transfer(taker, filled.amt);
        // SafeTransferLib.safeTransfer(ERC20(pair.base), taker, filled.amt);
        // protocol fee
        protocolFees[quote] += filled.protocolFee;

        // ensure receive enough quote token
        // _settle(quote, taker, filled.vol, msg.value);
        if (data.length > 0) {
            // always transfer ERC20 to msg.sender
            pair.base.transfer(msg.sender, filled.amt);
            uint256 balanceBefore = pair.quote.balanceOfSelf();
            IGridCallback(msg.sender).gridFillCallback(
                Currency.unwrap(pair.quote),
                Currency.unwrap(pair.base),
                filled.vol,
                filled.amt,
                data
            );
            require(
                balanceBefore + filled.vol <= pair.quote.balanceOfSelf(),
                "G3"
            );
        } else {
            _settleAssetWith(
                quote,
                pair.base,
                msg.sender,
                filled.vol,
                filled.amt,
                msg.value,
                flag
            );
        }
    }

    /// @inheritdoc IGridEx
    function fillBidOrder(
        uint256 gridOrderId,
        uint128 amt,
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    ) public payable override nonReentrant {
        // bool isAsk = isAskGridOrder(orderId);
        address taker = msg.sender;
        IGridOrder.OrderInfo memory orderInfo = getOrderInfo(gridOrderId, true);
        // IGridOrder.Order storage order = isAsk
        //     ? askOrders[orderId]
        //     : bidOrders[orderId];
        // IGridOrder.GridConfig storage gridConfig = gridConfigs[order.gridId];

        IGridOrder.OrderFillResult memory result = _fillBidOrder(
            amt,
            taker,
            orderInfo
        );

        if (minAmt > 0 && result.filledAmt < minAmt) {
            revert NotEnoughToFill();
        }

        IGridOrder.Order storage order = orderInfo.isAsk
            ? askOrders[orderInfo.orderId]
            : bidOrders[orderInfo.orderId];
        order.amount = result.orderAmt;
        order.revAmount = result.orderRevAmt;

        if (result.profit > 0) {
            // uint128 gridId = orderInfo.gridId;
            // IGridOrder.GridConfig storage gridConfig = gridConfigs[gridId];
            gridConfigs[orderInfo.gridId].profits += uint128(result.profit);
        }

        Pair memory pair = getPairById[orderInfo.pairId];
        // transfer quote token to taker
        // pair.quote.transfer(taker, filledVol);
        // SafeTransferLib.safeTransfer(ERC20(pair.quote), taker, filledVol);
        // protocol fee
        protocolFees[pair.quote] += result.protocolFee;

        // ensure receive enough base token
        // _settle(pair.base, taker, filledAmt, msg.value);
        uint128 outAmt = result.filledVol - result.lpFee - result.protocolFee;
        if (data.length > 0) {
            // always transfer ERC20 to msg.sender
            pair.quote.transfer(msg.sender, outAmt);
            uint256 balanceBefore = pair.base.balanceOfSelf();
            IGridCallback(msg.sender).gridFillCallback(
                Currency.unwrap(pair.base),
                Currency.unwrap(pair.quote),
                result.filledAmt,
                outAmt,
                data
            );
            require(
                balanceBefore + result.filledAmt <= pair.base.balanceOfSelf(),
                "G4"
            );
        } else {
            _settleAssetWith(
                pair.base,
                pair.quote,
                taker,
                result.filledAmt,
                outAmt,
                msg.value,
                flag
            );
        }
    }

    /// @inheritdoc IGridEx
    function fillBidOrders(
        uint64 pairId,
        uint256[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    ) public payable override nonReentrant {
        if (idList.length != amtList.length) {
            revert InvalidParam();
        }

        address taker = msg.sender;
        uint128 filledAmt = 0; // accumulate base amount
        uint128 filledVol = 0; // accumulate quote amount
        uint128 protocolFee = 0; // accumulate protocol fees

        for (uint256 i = 0; i < idList.length; ++i) {
            IGridOrder.OrderInfo memory orderInfo = getOrderInfo(
                idList[i],
                true
            );
            require(orderInfo.pairId == pairId, "G5");

            // uint96 orderId = idList[i];
            uint128 amt = amtList[i];

            if (maxAmt > 0 && maxAmt - filledAmt < amt) {
                amt = maxAmt - uint128(filledAmt);
            }

            // bool isAsk = isAskGridOrder(orderId);
            // IGridOrder.Order storage order = isAsk
            //     ? askOrders[orderId]
            //     : bidOrders[orderId];
            // IGridOrder.GridConfig storage gridConfig = gridConfigs[
            //     order.gridId
            // ];
            // require(gridConfig.pairId == pairId, "G7");
            IGridOrder.OrderFillResult memory result = _fillBidOrder(
                amt,
                taker,
                orderInfo
            );

            IGridOrder.Order storage order = orderInfo.isAsk
                ? askOrders[orderInfo.orderId]
                : bidOrders[orderInfo.orderId];
            order.amount = result.orderAmt;
            order.revAmount = result.orderRevAmt;

            if (result.profit > 0) {
                // uint128 gridId = orderInfo.gridId;
                // IGridOrder.GridConfig storage gridConfig = gridConfigs[gridId];
                gridConfigs[orderInfo.gridId].profits += uint128(result.profit);
            }

            filledAmt += result.filledAmt; // filledBaseAmt;
            filledVol += result.filledVol - result.lpFee - result.protocolFee; // filledQuoteAmtSubFee;
            protocolFee += result.protocolFee;

            if (maxAmt > 0 && filledAmt >= maxAmt) {
                break;
            }
        }

        if (minAmt > 0 && filledAmt < minAmt) {
            revert NotEnoughToFill();
        }

        Pair memory pair = getPairById[pairId];
        // transfer quote token to taker
        // pair.quote.transfer(taker, filledVol);
        // SafeTransferLib.safeTransfer(ERC20(pair.quote), taker, filledVol);
        // protocol fee
        protocolFees[pair.quote] += protocolFee;

        // ensure receive enough base token
        // _settle(pair.base, taker, filledAmt, msg.value);
        if (data.length > 0) {
            // always transfer ERC20 to msg.sender
            pair.quote.transfer(msg.sender, filledVol);
            uint256 balanceBefore = pair.base.balanceOfSelf();
            IGridCallback(msg.sender).gridFillCallback(
                Currency.unwrap(pair.base),
                Currency.unwrap(pair.quote),
                filledAmt,
                filledVol,
                data
            );
            require(
                balanceBefore + filledAmt <= pair.base.balanceOfSelf(),
                "G6"
            );
        } else {
            _settleAssetWith(
                pair.base,
                pair.quote,
                taker,
                filledAmt,
                filledVol,
                msg.value,
                flag
            );
        }
    }

    /// @inheritdoc IGridEx
    function getGridOrder(
        uint256 id
    ) public view override returns (IGridOrder.OrderInfo memory) {
        return getOrderInfo(id, false);
    }

    /// @inheritdoc IGridEx
    function getGridOrders(
        uint256[] calldata idList
    ) public view override returns (IGridOrder.OrderInfo[] memory) {
        IGridOrder.OrderInfo[] memory orderList = new IGridOrder.OrderInfo[](
            idList.length
        );

        for (uint256 i = 0; i < idList.length; i++) {
            orderList[i] = getOrderInfo(idList[i], false);
        }
        return orderList;
    }

    /// @inheritdoc IGridEx
    function getGridProfits(
        uint96 gridId
    ) public view override returns (uint256) {
        return gridConfigs[gridId].profits;
    }

    /// @inheritdoc IGridEx
    function getGridConfig(
        uint96 gridId
    ) public view override returns (IGridOrder.GridConfig memory) {
        return gridConfigs[gridId];
    }

    /// @inheritdoc IGridEx
    function withdrawGridProfits(
        uint128 gridId,
        uint256 amt,
        address to,
        uint32 flag
    ) public override {
        IGridOrder.GridConfig memory conf = gridConfigs[gridId];
        require(conf.owner == msg.sender, "G7");

        if (amt == 0) {
            amt = conf.profits;
        } else if (conf.profits < amt) {
            amt = conf.profits;
        }

        if (amt == 0) {
            revert NoProfits();
        }

        Pair memory pair = getPairById[conf.pairId];
        gridConfigs[gridId].profits = conf.profits - uint128(amt);
        // pair.quote.transfer(to, amt);
        _transferAssetTo(pair.quote, to, uint128(amt), flag);

        emit WithdrawProfit(gridId, pair.quote, to, amt);
    }

    function cancelGridOrders(
        address recipient,
        uint256 startGridOrderId,
        uint32 howmany,
        uint32 flag
    ) public override {
        uint128[] memory idList = new uint128[](howmany);
        (uint128 gridId, uint128 startOrderId) = extractGridIdOrderId(
            startGridOrderId
        );
        for (uint128 i = 0; i < howmany; ++i) {
            idList[i] = startOrderId + i;
        }

        cancelGridOrders(gridId, recipient, idList, flag);
    }

    /// @inheritdoc IGridEx
    function cancelGrid(
        address recipient,
        uint128 gridId,
        uint32 flag
    ) public override {
        IGridOrder.GridConfig memory gridConf = gridConfigs[gridId];
        if (msg.sender != gridConf.owner) {
            revert NotGridOwer();
        }

        if (gridConf.status != GridStatusNormal) {
            revert OrderCanceled();
        }

        uint256 baseAmt = 0;
        uint256 quoteAmt = 0;

        if (gridConf.askOrderCount > 0) {
            for (uint32 i = 0; i < gridConf.askOrderCount; i++) {
                uint128 orderId = gridConf.startAskOrderId + i;
                if (orderStatus[orderId] != GridStatusNormal) {
                    continue;
                }

                // do not set orderStatus to save gas
                // orderStatus[orderId] = GridStatusCanceled;

                (uint128 ba, uint128 qa) = getOrderAmountsForCancel(
                    gridConf,
                    orderId
                );
                unchecked {
                    baseAmt += ba;
                    quoteAmt += qa;
                }
            }
        }

        if (gridConf.bidOrderCount > 0) {
            for (uint32 i = 0; i < gridConf.bidOrderCount; i++) {
                uint128 orderId = gridConf.startBidOrderId + i;
                if (orderStatus[orderId] != GridStatusNormal) {
                    continue;
                }
                // do not set orderStatus to save gas
                // orderStatus[orderId] = GridStatusCanceled;

                (uint128 ba, uint128 qa) = getOrderAmountsForCancel(
                    gridConf,
                    orderId
                );
                unchecked {
                    baseAmt += ba;
                    quoteAmt += qa;
                }
            }
        }

        // clean grid profits
        if (gridConf.profits > 0) {
            quoteAmt += gridConf.profits;
            gridConfigs[gridId].profits = 0;
        }

        Pair memory pair = getPairById[gridConf.pairId];
        if (baseAmt > 0) {
            // transfer base
            // pair.base.transfer(recipient, baseAmt);
            _transferAssetTo(pair.base, recipient, baseAmt, flag & 0x1);
        }
        if (quoteAmt > 0) {
            // transfer
            // pair.quote.transfer(recipient, quoteAmt);
            _transferAssetTo(pair.quote, recipient, quoteAmt, flag & 0x2);
        }

        gridConfigs[gridId].status = GridStatusCanceled;
        emit CancelWholeGrid(msg.sender, gridId);
    }

    /// @inheritdoc IGridEx
    function cancelGridOrders(
        uint128 gridId,
        address recipient,
        uint128[] memory idList,
        uint32 flag
    ) public override {
        uint256 baseAmt = 0;
        uint256 quoteAmt = 0;

        IGridOrder.GridConfig memory gridConf = gridConfigs[gridId];
        if (msg.sender != gridConf.owner) {
            revert NotGridOwer();
        }

        if (gridConf.status != GridStatusNormal) {
            revert OrderCanceled();
        }

        for (uint128 i = 0; i < idList.length; ++i) {
            uint128 orderId = idList[i];
            if (orderStatus[orderId] != GridStatusNormal) {
                revert OrderCanceled();
            }

            (uint128 ba, uint128 qa) = getOrderAmountsForCancel(
                gridConf,
                orderId
            );
            unchecked {
                baseAmt += ba;
                quoteAmt += qa;
            }
            orderStatus[orderId] = GridStatusCanceled;
            emit CancelGridOrder(msg.sender, orderId, gridId);
            /*
            uint128 orderId = idList[i];


            IGridOrder.Order memory order;
            bool isAsk = isAskGridOrder(orderId);
            if (isAsk) {
                require(
                    orderId >= gridConf.startAskOrderId &&
                        orderId <
                        gridConf.startAskOrderId + gridConf.askOrderCount,
                    "GA"
                );

                order = askOrders[orderId];
                if (order.amount == 0 && order.revAmount == 0) {
                    unchecked {
                        baseAmt += gridConf.baseAmt;
                    }
                } else {
                    unchecked {
                        baseAmt += order.amount;
                        quoteAmt += order.revAmount;
                    }
                }
            } else {
                require(
                    orderId >= gridConf.startBidOrderId &&
                        orderId <
                        gridConf.startBidOrderId + gridConf.bidOrderCount,
                    "GB"
                );
                order = bidOrders[orderId];
                if (order.amount == 0 && order.revAmount == 0) {
                    uint160 price = gridConf.startBidPrice - (orderId - gridConf.startBidOrderId) * gridConf.askGap;
                    uint128 amt = calcQuoteAmount(gridConf.baseAmt, price, false);
                    unchecked {
                        quoteAmt += amt;
                    }
                } else {
                    unchecked {
                        baseAmt += order.revAmount;
                        quoteAmt += order.amount;
                    }
                }
            }
            */

            // if (isAsk) {
            //     delete askOrders[orderId];
            // } else {
            //     delete bidOrders[orderId];
            // }
        }

        // conf.orderCount -= uint32(idList.length);
        // if (conf.askOrderCount == 0 && conf.bidOrderCount == 0) {
        //     unchecked {
        //         quoteAmt += conf.profits;
        //     }
        //     delete gridConfigs[gridId];
        // }

        Pair memory pair = getPairById[gridConf.pairId];
        if (baseAmt > 0) {
            // transfer base
            // pair.base.transfer(recipient, baseAmt);
            _transferAssetTo(pair.base, recipient, baseAmt, flag & 0x1);
        }
        if (quoteAmt > 0) {
            // transfer
            // pair.quote.transfer(recipient, quoteAmt);
            _transferAssetTo(pair.quote, recipient, quoteAmt, flag & 0x2);
        }
    }

    //-------------------------------
    //------- Admin functions -------
    //-------------------------------

    /// @inheritdoc IGridEx
    function setQuoteToken(
        Currency token,
        uint256 priority
    ) external override onlyOwner {
        quotableTokens[token] = priority;

        emit QuotableTokenUpdated(token, priority);
    }

    /// @inheritdoc IGridEx
    function collectProtocolFee(
        Currency token,
        address recipient,
        uint256 amount,
        uint32 flag
    ) external override onlyOwner {
        if (amount == 0) {
            amount = protocolFees[token] - 1; // revert if overflow
        } else {
            amount = amount >= protocolFees[token]
                ? protocolFees[token] - 1 // revert if overflow
                : amount;
        }
        if (amount == 0) {
            return;
        }

        // token.transfer(recipient, amount);
        _transferAssetTo(token, recipient, amount, flag);
        protocolFees[token] -= amount;
    }
}
