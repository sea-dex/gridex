// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// import "./interfaces/IWETH.sol";
import {IPair} from "./interfaces/IPair.sol";
import {IGridOrder} from "./interfaces/IGridOrder.sol";
import {IGridEx} from "./interfaces/IGridEx.sol";
import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {IGridCallback} from "./interfaces/IGridCallback.sol";
import {IOrderErrors} from "./interfaces/IOrderErrors.sol";
import {IOrderEvents} from "./interfaces/IOrderEvents.sol";

import {Pair} from "./Pair.sol";
// import {GridOrder} from "./GridOrder.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";
import {GridOrder} from "./libraries/GridOrder.sol";
import {AssetSettle} from "./AssetSettle.sol";

import {Owned} from "solmate/auth/Owned.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

contract GridEx is
    IGridEx,
    AssetSettle,
    // GridOrder,
    Pair,
    Owned,
    ReentrancyGuard
{
    using SafeCast for *;
    using CurrencyLibrary for Currency;
    using GridOrder for GridOrder.GridState;

    address public vault;
    GridOrder.GridState internal _gridState;

    // mapping(Currency => uint256) public protocolProfits;

    constructor(address weth_, address usd_, address _vault) Owned(msg.sender) {
        // usd is the most priority quote token
        quotableTokens[Currency.wrap(usd_)] = 1 << 20;
        // quotableTokens[Currency.wrap(address(0))] = 1 << 19;
        quotableTokens[Currency.wrap(weth_)] = 1 << 19;
        WETH = weth_;
        vault = _vault;

        _gridState.initialize();
    }

    receive() external payable {}

    /// @inheritdoc IGridEx
    function getGridOrder(uint256 id) public view override returns (IGridOrder.OrderInfo memory) {
        return _gridState.getOrderInfo(id, false);
    }

    /// @inheritdoc IGridEx
    function getGridOrders(uint256[] calldata idList) public view override returns (IGridOrder.OrderInfo[] memory) {
        IGridOrder.OrderInfo[] memory orderList = new IGridOrder.OrderInfo[](idList.length);

        for (uint256 i = 0; i < idList.length; i++) {
            orderList[i] = _gridState.getOrderInfo(idList[i], false);
        }
        return orderList;
    }

    /// @inheritdoc IGridEx
    function getGridProfits(uint96 gridId) public view override returns (uint256) {
        return _gridState.gridConfigs[gridId].profits;
    }

    /// @inheritdoc IGridEx
    function getGridConfig(uint96 gridId) public view override returns (IGridOrder.GridConfig memory) {
        return _gridState.gridConfigs[gridId];
    }

    function placeETHGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param)
        public
        payable
    {
        bool baseIsETH = false;
        if (base.isAddressZero()) {
            baseIsETH = true;
            base = Currency.wrap(WETH);
        } else if (quote.isAddressZero()) {
            quote = Currency.wrap(WETH);
        } else {
            revert IOrderErrors.InvalidParam();
        }

        (, uint128 baseAmt, uint128 quoteAmt) = _placeGridOrders(msg.sender, base, quote, param);

        if (baseIsETH) {
            AssetSettle.transferETHFrom(msg.sender, baseAmt, uint128(msg.value));
            AssetSettle.transferTokenFrom(quote, msg.sender, quoteAmt);
        } else {
            AssetSettle.transferETHFrom(msg.sender, quoteAmt, uint128(msg.value));
            AssetSettle.transferTokenFrom(base, msg.sender, baseAmt);
        }
    }

    /// @inheritdoc IGridEx
    function placeGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param) public override {
        if (base.isAddressZero() || quote.isAddressZero()) {
            revert IOrderErrors.InvalidParam();
        }

        (Pair memory pair, uint128 baseAmt, uint128 quoteAmt) = _placeGridOrders(msg.sender, base, quote, param);

        // transfer base token
        if (baseAmt > 0) {
            AssetSettle.transferTokenFrom(pair.base, msg.sender, baseAmt);
        }

        // transfer quote token
        if (quoteAmt > 0) {
            AssetSettle.transferTokenFrom(pair.quote, msg.sender, quoteAmt);
        }
    }

    function _placeGridOrders(address maker, Currency base, Currency quote, IGridOrder.GridOrderParam calldata param)
        private
        returns (Pair memory pair, uint128 baseAmt, uint128 quoteAmt)
    {
        pair = getOrCreatePair(base, quote);

        uint256 startAskOrderId;
        uint256 startBidOrderId;
        uint128 gridId;
        (gridId, startAskOrderId, startBidOrderId, baseAmt, quoteAmt) =
            _gridState.placeGridOrder(pair.pairId, maker, param);

        emit IOrderEvents.GridOrderCreated(
            maker,
            pair.pairId,
            param.baseAmount,
            gridId,
            startAskOrderId,
            startBidOrderId,
            param.askOrderCount,
            param.bidOrderCount,
            param.fee,
            param.compound,
            param.oneshot
        );
    }

    function incProtocolProfits(Currency quote, uint128 profit) private {
        // Pair memory pair = getPairById[pairId];
        // transfer base token to taker
        // pair.base.transfer(taker, filledAmt);
        // SafeTransferLib.safeTransfer(ERC20(pair.base), taker, filledAmt);
        // protocol fee
        // protocolProfits[quote] += profit;
        quote.transfer(vault, profit);
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
        IGridOrder.OrderFillResult memory result = _gridState.fillAskOrder(gridOrderId, amt);

        if (minAmt > 0 && result.filledAmt < minAmt) {
            revert IOrderErrors.NotEnoughToFill();
        }

        emit IOrderEvents.FilledOrder(
            msg.sender, gridOrderId, result.filledAmt, result.filledVol, result.orderAmt, result.orderRevAmt, true
        );

        Pair memory pair = getPairById[result.pairId];
        // transfer base token to taker
        // pair.base.transfer(taker, filledAmt);
        // SafeTransferLib.safeTransfer(ERC20(pair.base), taker, filledAmt);
        // protocol fee
        // protocolProfits[pair.quote] += result.protocolFee;

        // ensure receive enough quote token
        // _settle(pair.quote, taker, filledVol, msg.value);

        uint128 inAmt = result.filledVol + result.lpFee + result.protocolFee;
        if (data.length > 0) {
            // always transfer ERC20 to msg.sender
            pair.base.transfer(msg.sender, result.filledAmt);
            uint256 balanceBefore = pair.quote.balanceOfSelf();
            IGridCallback(msg.sender).gridFillCallback(
                Currency.unwrap(pair.quote), Currency.unwrap(pair.base), inAmt, result.filledAmt, data
            );
            require(balanceBefore + inAmt <= pair.quote.balanceOfSelf(), "G1");
        } else {
            AssetSettle.settleAssetWith(pair.quote, pair.base, msg.sender, inAmt, result.filledAmt, msg.value, flag);
        }
        incProtocolProfits(pair.quote, result.protocolFee);
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
            revert IOrderErrors.InvalidParam();
        }

        // address taker = msg.sender;
        AccFilled memory filled;
        for (uint256 i = 0; i < idList.length; ++i) {
            uint256 gridOrderId = idList[i];
            // IGridOrder.OrderInfo memory orderInfo = getOrderInfo(
            //     idList[i],
            //     true
            // );

            // uint96 orderId = idList[i];
            uint128 amt = amtList[i];

            if (maxAmt > 0 && maxAmt < filled.amt + amt) {
                amt = maxAmt - filled.amt;
            }

            IGridOrder.OrderFillResult memory result = _gridState.fillAskOrder(gridOrderId, amt);
            require(result.pairId == pairId, "G2");

            emit IOrderEvents.FilledOrder(
                msg.sender, gridOrderId, result.filledAmt, result.filledVol, result.orderAmt, result.orderRevAmt, true
            );
            filled.amt += result.filledAmt;
            filled.vol += result.filledVol + result.lpFee + result.protocolFee;
            filled.protocolFee += result.protocolFee;

            if (maxAmt > 0 && filled.amt >= maxAmt) {
                break;
            }
        }

        if (minAmt > 0 && filled.amt < minAmt) {
            revert IOrderErrors.NotEnoughToFill();
        }

        Pair memory pair = getPairById[pairId];
        Currency quote = pair.quote;
        // transfer base token to taker
        // pair.base.transfer(taker, filled.amt);
        // SafeTransferLib.safeTransfer(ERC20(pair.base), taker, filled.amt);
        // protocol fee
        // protocolFees[quote] += filled.protocolFee;

        // ensure receive enough quote token
        // _settle(quote, taker, filled.vol, msg.value);
        if (data.length > 0) {
            // always transfer ERC20 to msg.sender
            pair.base.transfer(msg.sender, filled.amt);
            uint256 balanceBefore = pair.quote.balanceOfSelf();
            IGridCallback(msg.sender).gridFillCallback(
                Currency.unwrap(pair.quote), Currency.unwrap(pair.base), filled.vol, filled.amt, data
            );
            require(balanceBefore + filled.vol <= pair.quote.balanceOfSelf(), "G3");
        } else {
            AssetSettle.settleAssetWith(quote, pair.base, msg.sender, filled.vol, filled.amt, msg.value, flag);
        }
        incProtocolProfits(quote, filled.protocolFee);
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
        // address taker = msg.sender;
        // IGridOrder.OrderInfo memory orderInfo = getOrderInfo(gridOrderId, true);

        IGridOrder.OrderFillResult memory result = _gridState.fillBidOrder(gridOrderId, amt);

        if (minAmt > 0 && result.filledAmt < minAmt) {
            revert IOrderErrors.NotEnoughToFill();
        }

        // IGridOrder.Order storage order = orderInfo.isAsk
        //     ? askOrders[orderInfo.orderId]
        //     : bidOrders[orderInfo.orderId];
        // order.amount = result.orderAmt;
        // order.revAmount = result.orderRevAmt;

        // if (result.profit > 0) {
        // uint128 gridId = orderInfo.gridId;
        // IGridOrder.GridConfig storage gridConfig = gridConfigs[gridId];
        // gridConfigs[orderInfo.gridId].profits += uint128(result.profit);
        // }

        Pair memory pair = getPairById[result.pairId];
        // transfer quote token to taker
        // pair.quote.transfer(taker, filledVol);
        // SafeTransferLib.safeTransfer(ERC20(pair.quote), taker, filledVol);
        // protocol fee
        // protocolFees[pair.quote] += result.protocolFee;

        // ensure receive enough base token
        // _settle(pair.base, taker, filledAmt, msg.value);
        uint128 outAmt = result.filledVol - result.lpFee - result.protocolFee;
        if (data.length > 0) {
            // always transfer ERC20 to msg.sender
            pair.quote.transfer(msg.sender, outAmt);
            uint256 balanceBefore = pair.base.balanceOfSelf();
            IGridCallback(msg.sender).gridFillCallback(
                Currency.unwrap(pair.base), Currency.unwrap(pair.quote), result.filledAmt, outAmt, data
            );
            require(balanceBefore + result.filledAmt <= pair.base.balanceOfSelf(), "G4");
        } else {
            AssetSettle.settleAssetWith(pair.base, pair.quote, msg.sender, result.filledAmt, outAmt, msg.value, flag);
        }
        incProtocolProfits(pair.quote, result.protocolFee);
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
            revert IOrderErrors.InvalidParam();
        }

        address taker = msg.sender;
        uint128 filledAmt = 0; // accumulate base amount
        uint128 filledVol = 0; // accumulate quote amount
        uint128 protocolFee = 0; // accumulate protocol fees

        for (uint256 i = 0; i < idList.length; ++i) {
            // IGridOrder.OrderInfo memory orderInfo = getOrderInfo(
            //     idList[i],
            //     true
            // );

            // uint96 orderId = idList[i];
            uint256 gridOrderId = idList[i];
            uint128 amt = amtList[i];

            if (maxAmt > 0 && maxAmt - filledAmt < amt) {
                amt = maxAmt - uint128(filledAmt);
            }

            IGridOrder.OrderFillResult memory result = _gridState.fillBidOrder(gridOrderId, amt);
            // taker
            // orderInfo

            require(result.pairId == pairId, "G5");

            // IGridOrder.Order storage order = orderInfo.isAsk
            //     ? askOrders[orderInfo.orderId]
            //     : bidOrders[orderInfo.orderId];
            // order.amount = result.orderAmt;
            // order.revAmount = result.orderRevAmt;

            // if (result.profit > 0) {
            //     // uint128 gridId = orderInfo.gridId;
            //     // IGridOrder.GridConfig storage gridConfig = gridConfigs[gridId];
            //     gridConfigs[orderInfo.gridId].profits += uint128(result.profit);
            // }

            filledAmt += result.filledAmt; // filledBaseAmt;
            filledVol += result.filledVol - result.lpFee - result.protocolFee; // filledQuoteAmtSubFee;
            protocolFee += result.protocolFee;

            if (maxAmt > 0 && filledAmt >= maxAmt) {
                break;
            }
        }

        if (minAmt > 0 && filledAmt < minAmt) {
            revert IOrderErrors.NotEnoughToFill();
        }

        Pair memory pair = getPairById[pairId];
        // transfer quote token to taker
        // pair.quote.transfer(taker, filledVol);
        // SafeTransferLib.safeTransfer(ERC20(pair.quote), taker, filledVol);
        // protocol fee
        // protocolFees[pair.quote] += protocolFee;

        // ensure receive enough base token
        // _settle(pair.base, taker, filledAmt, msg.value);
        if (data.length > 0) {
            // always transfer ERC20 to msg.sender
            pair.quote.transfer(msg.sender, filledVol);
            uint256 balanceBefore = pair.base.balanceOfSelf();
            IGridCallback(msg.sender).gridFillCallback(
                Currency.unwrap(pair.base), Currency.unwrap(pair.quote), filledAmt, filledVol, data
            );
            require(balanceBefore + filledAmt <= pair.base.balanceOfSelf(), "G6");
        } else {
            AssetSettle.settleAssetWith(pair.base, pair.quote, taker, filledAmt, filledVol, msg.value, flag);
        }
        incProtocolProfits(pair.quote, protocolFee);
    }

    /// @inheritdoc IGridEx
    function withdrawGridProfits(uint128 gridId, uint256 amt, address to, uint32 flag) public override {
        IGridOrder.GridConfig memory conf = _gridState.gridConfigs[gridId];
        require(conf.owner == msg.sender, "G7");

        if (amt == 0) {
            amt = conf.profits;
        } else if (conf.profits < amt) {
            amt = conf.profits;
        }

        if (amt == 0) {
            revert IOrderErrors.NoProfits();
        }

        Pair memory pair = getPairById[conf.pairId];
        _gridState.gridConfigs[gridId].profits = conf.profits - uint128(amt);
        // pair.quote.transfer(to, amt);
        AssetSettle.transferAssetTo(pair.quote, to, uint128(amt), flag);

        emit WithdrawProfit(gridId, pair.quote, to, amt);
    }

    /// @inheritdoc IGridEx
    function cancelGrid(address recipient, uint128 gridId, uint32 flag) public override {
        // IGridOrder.GridConfig memory gridConf = gridConfigs[gridId];
        // if (msg.sender != gridConf.owner) {
        //     revert IOrderErrors.NotGridOwer();
        // }

        // if (gridConf.status != GridStatusNormal) {
        //     revert OrderCanceled();
        // }

        // uint256 baseAmt = 0;
        // uint256 quoteAmt = 0;

        // if (gridConf.askOrderCount > 0) {
        //     for (uint32 i = 0; i < gridConf.askOrderCount; i++) {
        //         uint128 orderId = gridConf.startAskOrderId + i;
        //         if (orderStatus[orderId] != GridStatusNormal) {
        //             continue;
        //         }

        //         // do not set orderStatus to save gas
        //         // orderStatus[orderId] = GridStatusCanceled;

        //         (uint128 ba, uint128 qa) = getOrderAmountsForCancel(
        //             gridConf,
        //             orderId
        //         );
        //         unchecked {
        //             baseAmt += ba;
        //             quoteAmt += qa;
        //         }
        //     }
        // }

        // if (gridConf.bidOrderCount > 0) {
        //     for (uint32 i = 0; i < gridConf.bidOrderCount; i++) {
        //         uint128 orderId = gridConf.startBidOrderId + i;
        //         if (orderStatus[orderId] != GridStatusNormal) {
        //             continue;
        //         }
        //         // do not set orderStatus to save gas
        //         // orderStatus[orderId] = GridStatusCanceled;

        //         (uint128 ba, uint128 qa) = getOrderAmountsForCancel(
        //             gridConf,
        //             orderId
        //         );
        //         unchecked {
        //             baseAmt += ba;
        //             quoteAmt += qa;
        //         }
        //     }
        // }

        // clean grid profits
        // if (gridConf.profits > 0) {
        //     quoteAmt += gridConf.profits;
        //     gridConfigs[gridId].profits = 0;
        // }

        (uint64 pairId, uint256 baseAmt, uint256 quoteAmt) = _gridState.cancelGrid(msg.sender, gridId);
        Pair memory pair = getPairById[pairId];
        if (baseAmt > 0) {
            // transfer base
            // pair.base.transfer(recipient, baseAmt);
            AssetSettle.transferAssetTo(pair.base, recipient, baseAmt, flag & 0x1);
        }
        if (quoteAmt > 0) {
            // transfer
            // pair.quote.transfer(recipient, quoteAmt);
            AssetSettle.transferAssetTo(pair.quote, recipient, quoteAmt, flag & 0x2);
        }

        emit IOrderEvents.CancelWholeGrid(msg.sender, gridId);
    }

    function cancelGridOrders(address recipient, uint256 startGridOrderId, uint32 howmany, uint32 flag)
        public
        override
    {
        uint256[] memory idList = new uint256[](howmany);
        (uint128 gridId,) = GridOrder.extractGridIdOrderId(startGridOrderId);
        for (uint256 i = 0; i < howmany; ++i) {
            idList[i] = startGridOrderId + i;
        }

        cancelGridOrders(gridId, recipient, idList, flag);
    }

    /// @inheritdoc IGridEx
    function cancelGridOrders(uint128 gridId, address recipient, uint256[] memory idList, uint32 flag)
        public
        override
    {
        // uint256 baseAmt = 0;
        // uint256 quoteAmt = 0;

        // IGridOrder.GridConfig memory gridConf = gridConfigs[gridId];
        // if (msg.sender != gridConf.owner) {
        //     revert NotGridOwer();
        // }

        // if (gridConf.status != GridStatusNormal) {
        //     revert OrderCanceled();
        // }

        // for (uint128 i = 0; i < idList.length; ++i) {
        //     uint128 orderId = idList[i];
        //     if (orderStatus[orderId] != GridStatusNormal) {
        //         revert OrderCanceled();
        //     }

        //     (uint128 ba, uint128 qa) = getOrderAmountsForCancel(
        //         gridConf,
        //         orderId
        //     );
        //     unchecked {
        //         baseAmt += ba;
        //         quoteAmt += qa;
        //     }
        //     orderStatus[orderId] = GridStatusCanceled;
        //     emit CancelGridOrder(msg.sender, orderId, gridId);
        // }

        (uint64 pairId, uint256 baseAmt, uint256 quoteAmt) = _gridState.cancelGridOrders(msg.sender, gridId, idList);

        Pair memory pair = getPairById[pairId];
        if (baseAmt > 0) {
            // transfer base
            // pair.base.transfer(recipient, baseAmt);
            AssetSettle.transferAssetTo(pair.base, recipient, baseAmt, flag & 0x1);
        }
        if (quoteAmt > 0) {
            // transfer
            // pair.quote.transfer(recipient, quoteAmt);
            AssetSettle.transferAssetTo(pair.quote, recipient, quoteAmt, flag & 0x2);
        }
    }

    //-------------------------------
    //------- Admin functions -------
    //-------------------------------

    /// @inheritdoc IGridEx
    function setQuoteToken(Currency token, uint256 priority) external override onlyOwner {
        quotableTokens[token] = priority;

        emit QuotableTokenUpdated(token, priority);
    }

    /// @inheritdoc IGridEx
    // function collectProtocolFee(
    //     Currency token,
    //     address recipient,
    //     uint256 amount,
    //     uint32 flag
    // ) external override onlyOwner {
    //     if (amount == 0) {
    //         amount = protocolProfits[token] - 1; // revert if overflow
    //     } else {
    //         amount = amount >= protocolProfits[token]
    //             ? protocolProfits[token] - 1 // revert if overflow
    //             : amount;
    //     }
    //     if (amount == 0) {
    //         return;
    //     }

    //     // token.transfer(recipient, amount);
    //     _transferAssetTo(token, recipient, amount, flag);
    //     protocolProfits[token] -= amount;
    // }
}
