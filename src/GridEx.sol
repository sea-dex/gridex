// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// import "./interfaces/IWETH.sol";
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

    // uint32 public constant ETHBase = 1;  // Base token is ETH
    // uint32 public constant ETHQuote = 2; // Quote token is ETH

    mapping(uint96 orderId => IGridOrder.Order) public bidOrders;
    mapping(uint96 orderId => IGridOrder.Order) public askOrders;
    mapping(Currency => uint256) public protocolFees;

    uint96 public nextGridId = 1;
    mapping(uint96 gridId => IGridOrder.GridConfig) public gridConfigs;

    constructor(address weth_, address usd_) Owned(msg.sender) {
        // usd is the most priority quote token
        quotableTokens[Currency.wrap(usd_)] = 1 << 20;
        // quotableTokens[Currency.wrap(address(0))] = 1 << 19;
        quotableTokens[Currency.wrap(weth_)] = 1 << 19;
        WETH = weth_;
    }

    function _createGridConfig(
        address maker,
        uint64 pairId,
        GridOrderParam calldata param
    ) private returns (uint96) {
        uint96 gridId = nextGridId++;

        gridConfigs[gridId] = IGridOrder.GridConfig({
            owner: maker,
            profits: 0,
            baseAmt: param.baseAmount,
            askGap: param.askGap,
            pairId: pairId,
            orderCount: param.askOrderCount + param.bidOrderCount,
            bidGap: param.bidGap,
            fee: param.fee,
            compound: param.compound
        });

        return gridId;
    }

    function placeETHGridOrders(
        Currency base,
        Currency quote,
        GridOrderParam calldata param
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

        (
            ,
            uint128 baseAmt,
            uint128 quoteAmt
        ) = _placeGridOrders(msg.sender, base, quote, param);

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
        GridOrderParam calldata param
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
        GridOrderParam calldata param
    ) private returns (Pair memory pair, uint128 baseAmt, uint128 quoteAmt) {
        pair = getOrCreatePair(base, quote);
        uint96 gridId = _createGridConfig(maker, pair.pairId, param);

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
            param.fee,
            gridId,
            pair.pairId,
            param.compound,
            startAskOrderId,
            startBidOrderId
        );
    }

    /// @inheritdoc IGridEx
    function fillAskOrder(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt, // base amount
        uint32 flag
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
        ) = _fillAskOrder(isAsk, orderId, amt, taker, order, gridConfig);

        if (minAmt > 0 && filledAmt < minAmt) {
            revert NotEnoughToFill();
        }

        Pair memory pair = getPairById[gridConfig.pairId];
        // transfer base token to taker
        // pair.base.transfer(taker, filledAmt);
        // SafeTransferLib.safeTransfer(ERC20(pair.base), taker, filledAmt);
        // protocol fee
        protocolFees[pair.quote] += protocolFee;

        // ensure receive enough quote token
        // _settle(pair.quote, taker, filledVol, msg.value);
        _settleAssetWith(pair.quote, pair.base, msg.sender, filledVol, filledAmt, msg.value, flag);
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
        uint128 minAmt, // base amount
        uint32 flag
    ) public payable override nonReentrant {
        if (idList.length != amtList.length) {
            revert InvalidParam();
        }

        address taker = msg.sender;
        AccFilled memory filled;
        for (uint256 i = 0; i < idList.length; ++i) {
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
            ) = _fillAskOrder(isAsk, orderId, amt, taker, order, gridConfig);

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
        // pair.base.transfer(taker, filled.amt);
        // SafeTransferLib.safeTransfer(ERC20(pair.base), taker, filled.amt);
        // protocol fee
        protocolFees[quote] += filled.fee;

        // ensure receive enough quote token
        // _settle(quote, taker, filled.vol, msg.value);
        _settleAssetWith(quote, pair.base, msg.sender, filled.vol, filled.amt, msg.value, flag);
    }

    /// @inheritdoc IGridEx
    function fillBidOrder(
        uint96 orderId,
        uint128 amt,
        uint128 minAmt, // base amount
        uint32 flag
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
        ) = _fillBidOrder(isAsk, orderId, amt, taker, order, gridConfig);

        if (minAmt > 0 && filledAmt < minAmt) {
            revert NotEnoughToFill();
        }

        Pair memory pair = getPairById[gridConfig.pairId];
        // transfer quote token to taker
        // pair.quote.transfer(taker, filledVol);
        // SafeTransferLib.safeTransfer(ERC20(pair.quote), taker, filledVol);
        // protocol fee
        protocolFees[pair.quote] += protocolFee;

        // ensure receive enough base token
        // _settle(pair.base, taker, filledAmt, msg.value);
        _settleAssetWith(pair.base, pair.quote, taker, filledAmt, filledVol, msg.value, flag);
    }

    /// @inheritdoc IGridEx
    function fillBidOrders(
        uint64 pairId,
        uint96[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt, // base amount
        uint128 minAmt, // base amount
        uint32 flag
    ) public payable override nonReentrant {
        if (idList.length != amtList.length) {
            revert InvalidParam();
        }

        address taker = msg.sender;
        uint256 filledAmt = 0; // accumulate base amount
        uint256 filledVol = 0; // accumulate quote amount
        uint256 protocolFee = 0;

        for (uint256 i = 0; i < idList.length; ++i) {
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
            ) = _fillBidOrder(isAsk, orderId, amt, taker, order, gridConfig);

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
        // pair.quote.transfer(taker, filledVol);
        // SafeTransferLib.safeTransfer(ERC20(pair.quote), taker, filledVol);
        // protocol fee
        protocolFees[pair.quote] += protocolFee;

        // ensure receive enough base token
        // _settle(pair.base, taker, filledAmt, msg.value);
        _settleAssetWith(pair.base, pair.quote, taker, filledAmt, filledVol, msg.value, flag);
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

        for (uint256 i = 0; i < idList.length; i++) {
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
        address to,
        uint32 flag
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
        // pair.quote.transfer(to, amt);
        _transferAssetTo(pair.quote, to, amt, flag);

        emit WithdrawProfit(gridId, pair.quote, to, amt);
    }

    function cancelGridOrders(
        uint96 gridId,
        address recipient,
        uint96 startOrderId,
        uint96 howmany,
        uint32 flag
    ) public override {
        uint96[] memory idList = new uint96[](howmany);
        for (uint96 i = 0; i < howmany; ++i) {
            idList[i] = startOrderId + i;
        }

        cancelGridOrders(gridId, recipient, idList, flag);
    }

    /// @inheritdoc IGridEx
    function cancelGridOrders(
        uint96 gridId,
        address recipient,
        uint96[] memory idList,
        uint32 flag
    ) public override {
        require(idList.length > 0, "G9");

        uint256 baseAmt = 0;
        uint256 quoteAmt = 0;

        IGridOrder.GridConfig storage conf = gridConfigs[gridId];
        if (msg.sender != conf.owner) {
            revert NotGridOwer();
        }

        for (uint256 i = 0; i < idList.length; ++i) {
            uint96 id = idList[i];
            IGridOrder.Order memory order;

            bool isAsk = isAskGridOrder(id);
            if (isAsk) {
                order = askOrders[id];
                unchecked {
                    baseAmt += order.amount;
                    quoteAmt += order.revAmount;
                }
            } else {
                order = bidOrders[id];
                unchecked {
                    baseAmt += order.revAmount;
                    quoteAmt += order.amount;
                }
            }
            require(order.gridId == gridId, "GA");

            emit CancelGridOrder(msg.sender, id, gridId);

            if (isAsk) {
                delete askOrders[id];
            } else {
                delete bidOrders[id];
            }
        }

        Pair memory pair = getPairById[conf.pairId];
        conf.orderCount -= uint32(idList.length);
        if (conf.orderCount == 0) {
            unchecked {
                quoteAmt += conf.profits;
            }
            delete gridConfigs[gridId];
        }

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
            amount = protocolFees[token] - 1;
        } else {
            amount = amount >= protocolFees[token]
                ? protocolFees[token] - 1
                : amount;
        }

        // token.transfer(recipient, amount);
        _transferAssetTo(token, recipient, amount, flag);
    }
}
