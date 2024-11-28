// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./interfaces/IWETH.sol";
import "./interfaces/IPair.sol";
import "./interfaces/IGridEx.sol";
import "./interfaces/IERC20Minimal.sol";

import {AssetSettle} from "./AssetSettle.sol";
import {Pair} from "./Pair.sol";
import {GridOrder} from "./GridOrder.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract GridEx is IGridEx, AssetSettle, GridOrder, Pair, Owned, ReentrancyGuard {
    using SafeCast for *;
    using CurrencyLibrary for Currency;

    address public immutable WETH;

    mapping(uint96 orderId => IGridOrder.Order) public bidOrders;
    mapping(uint96 orderId => IGridOrder.Order) public askOrders;
    mapping(Currency => uint) public protocolFees;

    uint96 public nextGridId = 1;
    mapping(uint96 gridId => IGridOrder.GridConfig) public gridConfigs;

    constructor(address weth_, address usd_) Owned(msg.sender) {
        // usd is the most priority quote token
        quotableTokens[Currency.wrap(usd_)] = 1 << 20;
        quotableTokens[Currency.wrap(address(0))] = 1 << 19;
        quotableTokens[Currency.wrap(weth_)] = 1 << 18;
        WETH = weth_;
    }

    function _createGridConfig(
        address maker,
        uint64 pairId,
        uint32 orderCount,
        uint32 fee,
        bool compound,
        uint128 baseAmt
    ) private returns (uint96) {
        uint96 gridId = nextGridId++;

        gridConfigs[gridId] = IGridOrder.GridConfig({
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

    /// @inheritdoc IGridEx
    function placeGridOrders(
        Currency base,
        Currency quote,
        GridOrderParam calldata param
    ) public payable override {
        (
            Pair memory pair,
            uint128 baseAmt,
            uint128 quoteAmt
        ) = _placeGridOrders(msg.sender, base, quote, param);

        // transfer base token
        if (baseAmt > 0) {
            _settle(pair.base, msg.sender, baseAmt, msg.value);
        }

        // transfer quote token
        if (quoteAmt > 0) {
            _settle(pair.quote, msg.sender, quoteAmt, msg.value);
        }
    }

    function _placeGridOrders(
        address maker,
        Currency base,
        Currency quote,
        GridOrderParam calldata param
    ) private returns (Pair memory pair, uint128 baseAmt, uint128 quoteAmt) {
        pair = getOrCreatePair(base, quote);
        uint96 gridId = _createGridConfig(
            maker,
            pair.pairId,
            param.askOrderCount + param.bidOrderCount,
            param.fee,
            param.compound,
            param.baseAmount
        );

        uint96 startAskOrderId;
        uint96 startBidOrderId;
        (startAskOrderId, baseAmt, startBidOrderId, quoteAmt) = placeGridOrder(
            gridId,
            param,
            askOrders,
            bidOrders
        );

        emit GridOrderCreated(
            msg.sender,
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

    /// @inheritdoc IGridEx
    function fillAskOrder(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) public payable override nonReentrant {
        bool isAsk = isAskGridOrder(orderId);
        address taker = msg.sender;
        IGridOrder.Order storage order = isAsk
            ? askOrders[orderId]
            : bidOrders[orderId];
        IGridOrder.GridConfig storage gridConfig = gridConfigs[order.gridId];

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
        pair.base.transfer(taker, filledAmt);
        // SafeTransferLib.safeTransfer(ERC20(pair.base), taker, filledAmt);
        // protocol fee
        protocolFees[pair.quote] += protocolFee;

        // ensure receive enough quote token
        _settle(pair.quote, taker, filledVol, msg.value);
    }

    struct AccFilled {
        uint256 amt; // base amount
        uint256 vol; // quote amount
        uint256 fee; // protocol fee
    }

    /// @inheritdoc IGridEx
    function fillAskOrders(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) public payable override nonReentrant {
        if (idList.length != amtList.length) {
            revert InvalidParam();
        }

        address taker = msg.sender;
        AccFilled memory filled;
        for (uint i = 0; i < idList.length; ++i) {
            uint96 orderId = idList[i];
            uint128 amt = amtList[i];

            if (maxAmt > 0 && maxAmt < filled.amt + amt) {
                amt = maxAmt - uint128(filled.amt);
            }

            bool isAsk = isAskGridOrder(orderId);
            IGridOrder.Order storage order = isAsk
                ? askOrders[orderId]
                : bidOrders[orderId];
            IGridOrder.GridConfig storage gridConfig = gridConfigs[
                order.gridId
            ];
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
        Currency quote = pair.quote;
        // transfer base token to taker
        pair.base.transfer(taker, filled.amt);
        // SafeTransferLib.safeTransfer(ERC20(pair.base), taker, filled.amt);
        // protocol fee
        protocolFees[quote] += filled.fee;

        // ensure receive enough quote token
        _settle(quote, taker, filled.vol, msg.value);
    }

    /// @inheritdoc IGridEx
    function fillBidOrder(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt // base amount
    ) public payable override nonReentrant {
        bool isAsk = isAskGridOrder(orderId);
        address taker = msg.sender;
        IGridOrder.Order storage order = isAsk
            ? askOrders[orderId]
            : bidOrders[orderId];
        IGridOrder.GridConfig storage gridConfig = gridConfigs[order.gridId];

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
        pair.quote.transfer(taker, filledVol);
        // SafeTransferLib.safeTransfer(ERC20(pair.quote), taker, filledVol);
        // protocol fee
        protocolFees[pair.quote] += protocolFee;

        // ensure receive enough base token
        _settle(pair.base, taker, filledAmt, msg.value);
    }

    /// @inheritdoc IGridEx
    function fillBidOrders(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt // base amount
    ) public payable override nonReentrant {
        if (idList.length != amtList.length) {
            revert InvalidParam();
        }

        address taker = msg.sender;
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
            IGridOrder.Order storage order = isAsk
                ? askOrders[orderId]
                : bidOrders[orderId];
            IGridOrder.GridConfig storage gridConfig = gridConfigs[
                order.gridId
            ];
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
        pair.quote.transfer(taker, filledVol);
        // SafeTransferLib.safeTransfer(ERC20(pair.quote), taker, filledVol);
        // protocol fee
        protocolFees[pair.quote] += protocolFee;

        // ensure receive enough base token
        _settle(pair.base, taker, filledAmt, msg.value);
    }

    /// @inheritdoc IGridEx
    function getGridOrder(
        uint96 id
    ) public view override returns (IGridOrder.Order memory order) {
        if (isAskGridOrder(id)) {
            order = askOrders[id];
        } else {
            order = bidOrders[id];
        }
    }

    /// @inheritdoc IGridEx
    function getGridOrders(
        uint96[] calldata idList
    ) public view override returns (IGridOrder.Order[] memory) {
        IGridOrder.Order[] memory orderList = new IGridOrder.Order[](
            idList.length
        );

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
        uint64 gridId,
        uint256 amt,
        address to
    ) public override {
        IGridOrder.GridConfig memory conf = gridConfigs[gridId];
        require(conf.owner == msg.sender);

        if (amt == 0) {
            amt = conf.profits;
        } else if (conf.profits < amt) {
            amt = conf.profits;
        }

        Pair memory pair = getPairById[conf.pairId];
        gridConfigs[gridId].profits = conf.profits - uint128(amt);
        pair.quote.transfer(to, amt);

        emit WithdrawProfit(gridId, pair.quote, to, amt);
    }

    /// @inheritdoc IGridEx
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
            IGridOrder.Order memory order;
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
            IGridOrder.GridConfig memory conf = gridConfigs[gridId];
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
            pair.base.transfer(recipient, totalBaseAmt);
        }
        if (quoteAmt > 0) {
            // transfer
            pair.quote.transfer(recipient, totalQuoteAmt);
        }
    }

    /// @inheritdoc IGridEx
    function setQuoteToken(
        Currency token,
        uint priority
    ) external override onlyOwner {
        quotableTokens[token] = priority;

        emit QuotableTokenUpdated(token, priority);
    }

    /// @inheritdoc IGridEx
    function collectProtocolFee(
        Currency token,
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

        token.transfer(recipient, amount);
    }
}
