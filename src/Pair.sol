// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "./interfaces/IPair.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPairDeployer.sol";

import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";
import "./libraries/TransferHelper.sol";

contract Pair is IPair {
    using CurrencyLibrary for Currency;
    using TransferHelper for IERC20Minimal;

    uint8 public constant BUY = 1;
    uint8 public constant SELL = 1;
    uint256 public constant PRICE_MULTIPLIER = 10 ** 30;

    /// @inheritdoc IPair
    address public immutable override factory;
    /// @inheritdoc IPair
    Currency public immutable override baseToken;
    /// @inheritdoc IPair
    Currency public immutable override quoteToken;

    struct Slot0 {
        /// @inheritdoc IPair
        uint24 fee;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }
    /// @inheritdoc IPair
    Slot0 public override slot0;

    /// @inheritdoc IPair
    uint256 public override protocolFees = 0;

    /// order
    struct Order {
        // order price
        uint160 price;
        // buy order: quote amount; sell order: base amount;
        uint96 amount;
        uint160 revPrice;
        uint96 revAmount;
        // grid id, or address if limit order
        uint64 gridId;
        // order id
        uint64 orderId;
    }

    mapping(uint64 orderId => Order) public bidOrders;
    mapping(uint64 orderId => Order) public askOrders;

    struct GridConfig {
        address owner;
        bool compound;
        uint32 orders;
        uint128 profits; // quote token
        uint96 baseAmt;
    }

    uint64 public nextGridId = 1;
    uint64 public nextBidOrderId = 1; // next grid order Id
    uint64 public nextAskOrderId = 0x8000000000000001;
    uint64 public constant AskOderMask = 0x8000000000000000;

    mapping(uint64 gridId => GridConfig) public gridConfigs;

    constructor() {
        uint24 _fee;
        address _base;
        address _quote;
        uint8 _feeProtocol;

        (factory, _base, _quote, _fee, _feeProtocol) = IPairDeployer(msg.sender).parameters();
        slot0.fee = _fee;
        slot0.feeProtocol = _feeProtocol;
        baseToken = Currency.wrap(_base);
        quoteToken = Currency.wrap(_quote);
    }

    // @inheritdoc IPair
    function fee() external view returns (uint24) {
        return slot0.fee;
    }

    // @inheritdoc IPair
    function feeProtocol() external view returns (uint8) {
        return slot0.feeProtocol;
    }

    struct GridOrderParam {
        uint256 sellPrice0;
        uint256 buyPrice0;
        uint256 sellGap;
        uint256 buyGap;
        uint96 baseAmount;
        uint16 asks;
        uint16 bids;
        bool compound;
    }

    function validateGridOrderParam(
        GridOrderParam calldata params
    ) private pure {
        uint256 sellPrice0 = params.sellPrice0;
        uint256 buyPrice0 = params.buyPrice0;
        uint256 sellGap = params.sellGap;
        uint256 buyGap = params.buyGap;
        uint256 asks = params.asks;
        uint256 bids = params.bids;

        // grid price
        if (sellPrice0 == 0 || buyPrice0 == 0 || sellPrice0 <= buyPrice0) {
            revert InvalidGridPrice();
        }
        if (
            sellPrice0 > uint256(type(uint160).max) ||
            buyPrice0 > uint256(type(uint160).max) ||
            sellGap >= uint256(type(uint160).max) ||
            buyGap >= uint256(type(uint160).max)
        ) {
            revert InvalidGridPrice();
        }

        if (sellGap >= sellPrice0) {
            revert InvalidGridPrice();
        }
        if (uint256(type(uint160).max) - buyPrice0 < buyGap) {
            revert InvalidGridPrice();
        }
        if (asks == 0 && bids == 0) {
            revert ZeroGridOrderCount();
        }

        // grid price gap
        uint96 perBaseAmt = params.baseAmount;
        uint256 baseAmt = 0;
        unchecked {
            if (
                asks > 1 &&
                sellPrice0 + uint256(asks - 1) * sellGap >=
                uint256(type(uint160).max)
            ) {
                revert InvalidGapPrice();
            }
            if (bids > 1 && uint256(bids - 1) * buyGap >= buyPrice0) {
                revert InvalidGapPrice();
            }
            baseAmt = uint256(perBaseAmt) * uint256(asks);
            if (baseAmt > type(uint96).max) {
                revert ExceedMaxAmount();
            }
        }
        // make sure the highest sell order quote amount not overflow
        if (asks > 0) {
            calcQuoteAmount(
                uint256(perBaseAmt),
                sellPrice0 + uint256(asks - 1) * sellGap
            );
        }
    }

    function isAskGridOrder(uint64 orderId) public pure returns (bool) {
        return orderId & AskOderMask > 0;
    }

    function placeGridOrders(GridOrderParam calldata params) public {
        // validate grid params
        validateGridOrderParam(params);
        uint64 gridId = nextGridId;
        uint64 askOrderId = 0;
        uint64 bidOrderId = 0;

        if (params.asks > 0) {
            askOrderId = nextAskOrderId;
            unchecked {
                if (type(uint64).max - params.asks < askOrderId) {
                    revert ExceedMaxAskOrder();
                }
                nextAskOrderId = askOrderId + params.asks;
            }
            // only create order0, other orders will be lazy created
            uint256 sellPrice0 = params.sellPrice0;
            uint256 sellGap = params.sellGap;
            for (uint i = 0; i < params.asks; ) {
                askOrders[askOrderId] = Order({
                    gridId: gridId,
                    orderId: askOrderId,
                    amount: uint96(params.baseAmount),
                    revAmount: 0,
                    price: uint160(sellPrice0),
                    revPrice: uint160(sellPrice0 - sellGap)
                });
                unchecked {
                    ++i;
                    ++askOrderId;
                    sellPrice0 += sellGap;
                }
            }
            IERC20Minimal(Currency.unwrap(baseToken)).safeTransferFrom(
                msg.sender,
                address(this),
                params.asks * params.baseAmount
            );
        }

        if (params.bids > 0) {
            uint256 buyPrice0 = params.buyPrice0;
            uint256 buyGap = params.buyGap;
            uint256 perBaseAmt = params.baseAmount;
            uint256 quoteAmt = 0;
            // create bid orders
            bidOrderId = nextBidOrderId;

            unchecked {
                if (AskOderMask - params.bids < bidOrderId) {
                    revert ExceedMaxBidOrder();
                }
                nextBidOrderId = bidOrderId + params.bids;

                for (uint i = 0; i < params.bids; ) {
                    uint256 price = buyPrice0 - i * buyGap;
                    uint256 amt = calcQuoteAmount(perBaseAmt, price);

                    bidOrders[bidOrderId] = Order({
                        gridId: gridId,
                        orderId: bidOrderId,
                        amount: uint96(amt),
                        price: uint160(price),
                        revPrice: uint160(price + buyGap),
                        revAmount: 0
                    });

                    quoteAmt += amt;
                    ++i;
                    ++bidOrderId;
                }
            }
            // transfer base/quote tokens
            if (quoteAmt > type(uint160).max) {
                revert ExceedMaxAmount();
            }
            IERC20Minimal(Currency.unwrap(quoteToken)).safeTransferFrom(
                msg.sender,
                address(this),
                quoteAmt
            );
        }

        unchecked {
            // we don't think this would overflow
            ++nextGridId;
        }
        // initialize owner's grid config
        gridConfigs[uint64(gridId)] = GridConfig({
            owner: msg.sender,
            orders: uint32(params.asks + params.bids),
            profits: 0,
            compound: params.compound,
            baseAmt: params.baseAmount
        });

        emit GridOrderCreated(
            msg.sender,
            params.asks,
            params.bids,
            uint64(gridId),
            askOrderId,
            bidOrderId,
            params.sellPrice0,
            params.sellGap,
            params.buyPrice0,
            params.buyGap,
            params.baseAmount,
            params.compound
        );
    }

    function calcQuoteAmount(
        uint256 baseAmt,
        uint256 price
    ) public pure returns (uint256) {
        uint256 amt = 0;
        unchecked {
            amt = ((baseAmt) * (price)) / PRICE_MULTIPLIER;
        }
        if (amt == 0) {
            revert ZeroQuoteAmt();
        }
        if (amt >= uint256(type(uint96).max)) {
            revert ExceedQuoteAmt();
        }
        return amt;
    }

    function calcBaseAmount(
        uint256 quoteAmt,
        uint256 price
    ) public pure returns (uint256) {
        uint256 amt = 0;
        unchecked {
            amt = (((quoteAmt) * PRICE_MULTIPLIER) / (price));
        }
        if (amt == 0) {
            revert ZeroBaseAmt();
        }
        if (amt >= uint256(type(uint96).max)) {
            revert ExceedBaseAmt();
        }
        return amt;
    }

    // amount is always quote amount
    function collectProtocolFee(
        uint256 amount
    ) public returns (uint256, uint256) {
        uint256 totalFee;
        uint256 protoFee = 0;

        unchecked {
            totalFee = (uint256(slot0.fee) * uint256(amount)) / 1000000;
            uint8 feeProto = slot0.feeProtocol;
            if (feeProto > 0) {
                protoFee = totalFee / uint256(feeProto);
                protocolFees += uint128(protoFee);
            }
        }

        return (totalFee, totalFee - protoFee);
    }

    function fillAskOrder(
        address taker,
        uint64 id,
        uint256 amt
    ) private returns (uint256, uint256) {
        // copy order to memory, save gas
        Order memory order;
        uint256 sellPrice;
        uint256 orderBaseAmt; // base token amount of the grid order
        uint256 orderQuoteAmt; // quote token amount of the grid order
        bool isAsk = isAskGridOrder(id);

        if (isAsk) {
            order = askOrders[id];
            if (order.amount == 0) {
                return (0, 0);
            }
            orderBaseAmt = order.amount;
            orderQuoteAmt = order.revAmount;
            sellPrice = order.price;
        } else {
            order = bidOrders[id];
            // rev amount is base token
            if (order.revAmount == 0) {
                return (0, 0);
            }
            orderBaseAmt = order.revAmount;
            orderQuoteAmt = order.amount;
            sellPrice = order.revPrice;
        }

        if (amt > orderBaseAmt) {
            amt = orderBaseAmt;
        }
        uint256 vol = calcQuoteAmount(amt, uint256(sellPrice)); // quoteVol = filled * price
        (uint256 totalFee, uint256 lpFee) = collectProtocolFee(vol);
        unchecked {
            if (vol + totalFee > type(uint96).max) {
                revert ExceedQuoteAmt();
            }
        }

        unchecked {
            orderBaseAmt -= amt;
        }
        // avoid stacks too deep
        {
            uint64 gridId = order.gridId;
            if (gridConfigs[gridId].compound) {
                orderQuoteAmt += vol + lpFee; // all quote reverse
                if (orderQuoteAmt > type(uint96).max) {
                    revert ExceedQuoteAmt();
                }
            } else {
                uint256 base = gridConfigs[gridId].baseAmt;
                uint256 buyPrice = isAsk ? order.revPrice : order.price;
                uint256 quota = calcQuoteAmount(base, buyPrice);
                // increase profit if sell quote amount > baseAmt * price
                unchecked {
                    if (orderQuoteAmt >= quota) {
                        gridConfigs[gridId].profits += uint128(vol + lpFee);
                    } else {
                        uint256 rev = orderQuoteAmt + vol + lpFee;
                        if (rev > quota) {
                            orderQuoteAmt = quota;
                            gridConfigs[gridId].profits += uint128(rev - quota);
                        } else {
                            orderQuoteAmt += vol + lpFee;
                        }
                    }
                }
            }
        }
        emit FilledOrder(
            order.orderId,
            1<<160 | sellPrice, // ASK
            amt,
            vol,
            orderBaseAmt,
            orderQuoteAmt,
            totalFee,
            lpFee,
            taker
        );

        // update storage order
        if (isAsk) {
            askOrders[id].amount = uint96(orderBaseAmt);
            askOrders[id].revAmount = uint96(orderQuoteAmt);
        } else {
            bidOrders[id].amount = uint96(orderQuoteAmt);
            bidOrders[id].revAmount = uint96(orderBaseAmt);
        }

        return (amt, vol + totalFee);
    }

    // taker is BUY
    function fillAskOrders(
        uint64 id,
        uint256 amt,
        uint256 maxAmt, // base amount
        uint256 minAmt // base amount
    ) public {
        if (maxAmt > 0) require(maxAmt >= amt);
        if (minAmt > 0) require(minAmt <= amt);

        (uint256 filledAmt, uint256 filledVol) = fillAskOrder(msg.sender, id, amt);

        if (minAmt > 0 && filledAmt < minAmt) {
            revert NotEnoughToFill();
        }

        if (filledVol > 0) {
            IERC20Minimal(Currency.unwrap(quoteToken)).safeTransferFrom(
                msg.sender,
                address(this),
                filledVol
            );
            // transfer base token to taker
            baseToken.transfer(msg.sender, filledAmt);
        }
    }

    // taker is BUY
    function fillAskOrders(
        uint64[] calldata idList,
        uint256[] calldata amtList,
        uint256 maxAmt, // base amount
        uint256 minAmt // base amount
    ) public {
        if (idList.length != amtList.length) {
            revert InvalidParam();
        }

        uint256 filledAmt = 0; // accumulate base amount
        uint256 filledVol = 0; // accumulate quote amount

        for (uint i = 0; i < idList.length; ) {
            uint256 amt = amtList[i];

            if (maxAmt > 0 && maxAmt - filledAmt < amt) {
                amt = maxAmt - filledAmt;
            }

            (
                uint256 filledBaseAmt,
                uint256 filledQuoteAmtWithFee
            ) = fillAskOrder(msg.sender, idList[i], amt);

            unchecked {
                filledAmt += filledBaseAmt;
                filledVol += filledQuoteAmtWithFee;
                ++i;
            }

            if (maxAmt > 0 && filledAmt >= maxAmt) {
                break;
            }
        }

        if (minAmt > 0 && filledAmt < minAmt) {
            revert NotEnoughToFill();
        }
        if (filledVol > 0) {
            IERC20Minimal(Currency.unwrap(quoteToken)).safeTransferFrom(
                msg.sender,
                address(this),
                filledVol
            );
            // transfer base token to taker
            baseToken.transfer(msg.sender, filledAmt);
        }
    }

    // amt is base token
    function fillBidOrder(
        address taker,
        uint64 id,
        uint256 amt
    ) private returns (uint256, uint256) {
        // copy order to memory, save gas
        Order memory order;
        uint256 buyPrice;
        uint256 orderBaseAmt; // base token amount of the grid order
        uint256 orderQuoteAmt; // quote token amount of the grid order
        bool isAsk = isAskGridOrder(id);

        if (isAsk) {
            order = askOrders[id];
            if (order.revAmount == 0) {
                return (0, 0);
            }
            orderBaseAmt = order.amount;
            orderQuoteAmt = order.revAmount;
            buyPrice = order.revPrice;
        } else {
            order = bidOrders[id];
            // amount is quote token
            if (order.amount == 0) {
                return (0, 0);
            }
            orderBaseAmt = order.revAmount;
            orderQuoteAmt = order.amount;
            buyPrice = order.price;
        }
        uint256 filledVol = calcQuoteAmount(amt, buyPrice);
        if (filledVol > orderQuoteAmt) {
            amt = calcBaseAmount(orderQuoteAmt, buyPrice);
            filledVol = orderQuoteAmt; // calcQuoteAmount(amt, buyPrice);
        }
        (uint256 totalFee, uint256 lpFee) = collectProtocolFee(filledVol);
        unchecked {
            if (filledVol + totalFee > type(uint96).max) {
                revert ExceedQuoteAmt();
            }
        }
        unchecked {
            orderBaseAmt += amt;
        }

        // avoid stacks too deep
        {
            uint64 gridId = order.gridId;
            if (gridConfigs[gridId].compound) {
                orderQuoteAmt -= filledVol - lpFee; // all quote reverse
            } else {
                // lpFee into profit
                gridConfigs[gridId].profits += uint128(lpFee);
                orderQuoteAmt -= filledVol;
            }
        }

        emit FilledOrder(
            order.orderId,
            2<<160 | buyPrice, // BID
            amt,
            filledVol,
            orderBaseAmt,
            orderQuoteAmt,
            totalFee,
            lpFee,
            taker
        );

        // update storage order
        if (isAsk) {
            askOrders[id].amount = uint96(orderBaseAmt);
            askOrders[id].revAmount = uint96(orderQuoteAmt);
        } else {
            bidOrders[id].amount = uint96(orderQuoteAmt);
            bidOrders[id].revAmount = uint96(orderBaseAmt);
        }

        return (amt, filledVol - totalFee);
    }

    // taker is sell, amtList, maxAmt, minAmt is base token amount
    function fillBidOrders(
        uint64 id,
        uint256 amt,
        uint256 maxAmt,
        uint256 minAmt // base amount
    ) public {
        if (maxAmt > 0) require(maxAmt >= amt);
        if (minAmt > 0) require(minAmt <= amt);

        (uint256 filledAmt, uint256 filledVol) = fillBidOrder(msg.sender, id, amt);

        if (minAmt > 0 && filledAmt < minAmt) {
            revert NotEnoughToFill();
        }
        if (filledVol > 0) {
            // transfer quote token to taker
            quoteToken.transfer(msg.sender, filledVol);
            // transfer base token from taker

            IERC20Minimal(Currency.unwrap(baseToken)).safeTransferFrom(
                msg.sender,
                address(this),
                filledAmt
            );
        }
    }

    // taker is sell, amtList, maxAmt, minAmt is base token amount
    function fillBidOrders(
        uint64[] calldata idList,
        uint96[] calldata amtList,
        uint256 maxAmt,
        uint256 minAmt // base amount
    ) public {
        if (idList.length != amtList.length) {
            revert InvalidParam();
        }

        uint256 filledAmt = 0; // accumulate base amount
        uint256 filledVol = 0; // accumulate quote amount

        for (uint i = 0; i < idList.length; ) {
            uint256 amt = amtList[i];

            if (maxAmt > 0 && maxAmt - filledAmt < amt) {
                amt = maxAmt - filledAmt;
            }

            (
                uint256 filledBaseAmt,
                uint256 filledQuoteAmtSubFee
            ) = fillBidOrder(msg.sender, idList[i], amt);

            unchecked {
                filledAmt += filledBaseAmt;
                filledVol += filledQuoteAmtSubFee;
                ++i;
            }

            if (maxAmt > 0 && filledAmt >= maxAmt) {
                break;
            }
        }

        if (minAmt > 0 && filledAmt < minAmt) {
            revert NotEnoughToFill();
        }
        if (filledVol > 0) {
            // transfer quote token to taker
            quoteToken.transfer(msg.sender, filledVol);
            // transfer base token from taker

            IERC20Minimal(Currency.unwrap(baseToken)).safeTransferFrom(
                msg.sender,
                address(this),
                filledAmt
            );
        }
    }

    function getGridOrder(uint64 id) public view returns (Order memory order) {
        if (isAskGridOrder(id)) {
            order = askOrders[id];
        } else {
            order = bidOrders[id];
        }
    }

    function getGridOrders(
        uint64[] calldata idList
    ) public view returns (Order[] memory) {
        Order[] memory orderList = new Order[](idList.length);

        for (uint i = 0; i < idList.length; i++) {
            uint64 id = idList[i];
            if (isAskGridOrder(idList[i])) {
                orderList[i] = askOrders[id];
            } else {
                orderList[i] = bidOrders[id];
            }
        }
        return orderList;
    }

    function getGridProfits(uint64 gridId) public view returns (uint256) {
        return gridConfigs[gridId].profits;
    }

    function sweepGridProfits(uint64 gridId, uint256 amt, address to) public {
        GridConfig memory conf = gridConfigs[gridId];
        require(conf.owner == msg.sender);

        if (conf.profits > amt) {
            amt = conf.profits;
        }
        if (amt == 0) {
            return;
        }

        gridConfigs[gridId].profits = conf.profits - uint128(amt);
        IERC20Minimal(Currency.unwrap(quoteToken)).safeTransferFrom(
            msg.sender,
            to,
            amt
        );
    }

    // cancel grid order will cancel both ask order and bid order
    function cancelGridOrders(uint64[] calldata idList) public {
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
            uint64 gridId = order.gridId;
            GridConfig memory conf = gridConfigs[gridId];
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
                --conf.orders;
                totalBaseAmt += baseAmt;
                totalQuoteAmt += quoteAmt;
            }
            if (conf.orders == 0) {
                delete gridConfigs[gridId];
            }
        }
        if (baseAmt > 0) {
            // transfer
            baseToken.transfer(msg.sender, totalBaseAmt);
        }
        if (quoteAmt > 0) {
            // transfer
            quoteToken.transfer(msg.sender, totalQuoteAmt);
        }
    }

    /// @inheritdoc IPair
    function setFeeProtocol(uint8 _feeProtocol) external override {
        require(msg.sender == IFactory(factory).owner());

        require(_feeProtocol == 0 || (_feeProtocol >= 4 && _feeProtocol <= 10));
        uint8 feeProtocolOld = slot0.feeProtocol;
        slot0.feeProtocol = _feeProtocol;
        emit SetFeeProtocol(feeProtocolOld, _feeProtocol);
    }

    /// @inheritdoc IPair
    function collectProtocol(
        address recipient,
        uint256 amount
    ) external override returns (uint256) {
        require(msg.sender == IFactory(factory).owner());

        amount = amount > protocolFees ? protocolFees : amount;

        if (amount > 0) {
            if (amount == protocolFees) amount--; // ensure that the slot is not cleared, for gas savings
            protocolFees -= amount;
            quoteToken.transfer(recipient, amount);

            emit CollectProtocol(msg.sender, recipient, amount);
        }

        return amount;
    }
}
