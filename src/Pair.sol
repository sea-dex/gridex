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

    uint8 constant BUY = 1;
    uint8 constant SELL = 1;
    uint256 constant PRICE_MULTIPLIER = 10 ** 30;

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
        // grid id, or address if limit order
        uint64 gridId;
        // order id
        uint64 orderId;
        // buy order: quote amount; sell order: base amount;
        uint96 amount;
        // order price
        uint160 price;
    }

    mapping(uint64 orderId => Order) public bidOrders;
    mapping(uint64 orderId => Order) public askOrders;

    struct GridConfig {
        address owner;
        uint32 orders;
    }

    uint64 public nextGridId = 1;
    uint64 public nextOrderId = 1; // next grid order Id
    mapping(uint64 gridId => GridConfig) public gridConfigs;

    constructor() {
        uint24 _fee;
        address _base;
        address _quote;
    
        (factory, _base, _quote, _fee) = IPairDeployer(msg.sender).parameters();
        slot0.fee = _fee;
        baseToken = Currency.wrap(_base);
        quoteToken = Currency.wrap(_quote);
    }

    // make the pair contract send/receive ETH
    receive() external payable {}

    // @inheritdoc IPair
    function fee() external view returns (uint24) {
        return slot0.fee;
    }

    struct GridOrderParam {
        uint256 sellPrice0;
        uint256 buyPrice0;
        uint256 sellGap;
        uint256 buyGap;
        uint96 baseAmount;
        uint16 asks;
        uint16 bids;
    }

    function validateGridOrderParam(
        GridOrderParam calldata params
    ) private pure returns (uint256) {
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
            if (baseAmt > type(uint160).max) {
                revert ExceedMaxAmount();
            }
        }
        return baseAmt;
    }

    function placeGridOrders(GridOrderParam calldata params) public payable {
        // validate grid params
        uint256 baseAmt = validateGridOrderParam(params);

        uint64 gridId = nextGridId;
        uint256 quoteAmt = 0;

        // initialize owner's grid config
        GridConfig storage gridConf = gridConfigs[uint64(gridId)];
        gridConf.owner = msg.sender;
        unchecked {
            // we don't think this would overflow
            ++nextGridId;
            gridConf.orders = uint32(params.asks + params.bids);
        }

        uint64 orderId = nextOrderId;
        {
            uint256 sellPrice0 = params.sellPrice0;
            uint256 sellGap = params.sellGap;
            uint256 buyPrice0 = params.buyPrice0;
            uint256 buyGap = params.buyGap;
            uint96 perBaseAmt = params.baseAmount;

            // create ask orders
            for (uint i = 0; i < params.asks; ) {
                Order storage askOrder = askOrders[orderId];
                Order storage revOrder = bidOrders[orderId];

                askOrder.gridId = gridId;
                askOrder.orderId = orderId;
                askOrder.amount = perBaseAmt;
                revOrder.gridId = gridId;
                revOrder.orderId = orderId;
                revOrder.amount = 0;

                unchecked {
                    ++i;
                    ++orderId;
                    if (orderId == type(uint64).max) {
                        revert ExceedMaxOrder();
                    }
                    uint160 price = uint160(sellPrice0 + i * sellGap);
                    askOrder.price = price;
                    revOrder.price = uint160(price - sellGap);
                }
            }

            // create bid orders
            for (uint i = 0; i < params.bids; ) {
                Order storage bidOrder = bidOrders[orderId];
                Order storage revOrder = askOrders[orderId];

                bidOrder.gridId = gridId;
                bidOrder.orderId = orderId;
                revOrder.gridId = gridId;
                revOrder.orderId = orderId;
                revOrder.amount = 0;

                unchecked {
                    ++i;
                    ++orderId;
                    if (orderId == type(uint64).max) {
                        revert ExceedMaxOrder();
                    }
                    uint160 price = uint160(buyPrice0 - i * buyGap);
                    bidOrder.price = price;
                    revOrder.price = uint160(price + buyGap);
                    uint96 amt = calcQuoteAmount(perBaseAmt, price);
                    bidOrder.amount = amt;
                    quoteAmt += amt;
                }
            }
        }
        nextOrderId = orderId;
        // transfer base/quote tokens
        if (baseAmt > 0) {
            if (baseToken.isNative()) {
                if (msg.value < baseAmt) revert NotEnoughBaseToken();
                // refund
                if (msg.value > baseAmt) {
                    baseToken.transfer(msg.sender, msg.value-baseAmt);
                }
            } else {
                IERC20Minimal(Currency.unwrap(baseToken)).safeTransferFrom(
                    msg.sender,
                    address(this),
                    baseAmt
                );
            }
        }
        if (quoteAmt > 0) {
            if (quoteAmt > type(uint160).max) {
                revert ExceedMaxAmount();
            }
            if (quoteToken.isNative()) {
                if (msg.value < quoteAmt) revert NotEnoughQuoteToken();
                // refund
                if (msg.value > quoteAmt) {
                    quoteToken.transfer(msg.sender, msg.value-quoteAmt);
                }
            } else {
                IERC20Minimal(Currency.unwrap(quoteToken)).safeTransferFrom(
                    msg.sender,
                    address(this),
                    quoteAmt
                );
            }
        }

        emit GridOrderCreated(
            msg.sender,
            params.asks,
            params.bids,
            uint64(gridId),
            orderId,
            params.sellPrice0,
            params.sellGap,
            params.buyPrice0,
            params.buyGap,
            params.baseAmount
        );
    }

    function calcQuoteAmount(
        uint96 baseAmt,
        uint160 price
    ) public pure returns (uint96) {
        uint256 amt = 0;
        unchecked {
            amt = (uint256(baseAmt) * uint256(price)) / PRICE_MULTIPLIER;
        }
        if (amt == 0) {
            revert ZeroQuoteAmt();
        }
        if (amt >= uint256(type(uint96).max)) {
            revert ExceedQuoteAmt();
        }
        return uint96(amt);
    }

    function calcBaseAmount(
        uint96 quoteAmt,
        uint160 price) public pure returns (uint96) {
        uint256 amt = 0;
        unchecked {
            amt = (uint256(quoteAmt) * PRICE_MULTIPLIER / uint256(price));
        }
        if (amt == 0) {
            revert ZeroBaseAmt();
        }
        if (amt >= uint256(type(uint96).max)) {
            revert ExceedBaseAmt();
        }
        return uint96(amt);

    }

    // amount is always quote amount
    function calcFee(uint96 amount) public returns (uint96, uint96) {
        uint96 totalFee;
        uint96 protoFee = 0;

        unchecked {
            totalFee = uint96((uint256(slot0.fee) * uint256(amount)) / 1000000);
            if (slot0.feeProtocol > 0) {
                protoFee = totalFee / uint96(slot0.feeProtocol);
                protocolFees += uint128(protoFee);
            }
        }

        return (totalFee, totalFee - protoFee);
    }

    // taker is BUY
    function fillAskOrders(
        uint64[] calldata idList,
        uint96[] calldata amtList,
        uint256 maxAmt, // base amount
        uint256 minAmt // base amount
    ) public payable {
        if (idList.length != amtList.length) {
            revert InvalidParam();
        }

        uint256 filledAmt = 0; // accumulate base amount
        uint256 filledVol = 0; // accumulate quote amount
        uint256 filledFee = 0; // accumulate fee, by quote

        for (uint i = 0; i < idList.length; ) {
            uint64 id = idList[i];
            uint96 filled = amtList[i];
            Order storage order = askOrders[id];
            uint96 amount = order.amount;

            if (amount == 0) {
                // order NOT exist or filled
                unchecked {
                    ++i;
                }
                continue;
            }

            if (amount < filled) {
                filled = amount;
            }
            if (maxAmt > 0 && maxAmt - filledAmt < filled) {
                filled = uint96(maxAmt - filledAmt);
            }
            order.amount -= filled;
            uint96 vol = calcQuoteAmount(filled, order.price) + 1; // quoteVol = filled * price
            (uint96 totalFee, uint96 lpFee) = calcFee(vol);

            emit FilledOrder(order.orderId, vol, totalFee, lpFee);

            Order storage bidOrder = bidOrders[id];
            // all sell and fee go to reversed grid order
            bidOrder.amount += vol + lpFee;

            unchecked {
                filledAmt += filled;
                filledVol += vol;
                filledFee += totalFee;
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
            // transfer quote token from taker
            filledVol += filledFee;
            if (quoteToken.isNative()) {
                if (msg.value < filledVol) revert NotEnoughQuoteToken();
                if (msg.value > filledVol) {
                    // refund
                    quoteToken.transfer(msg.sender, msg.value - filledVol);
                }
            } else {
                IERC20Minimal(Currency.unwrap(quoteToken)).safeTransferFrom(
                    msg.sender,
                    address(this),
                    filledVol
                );
            }
            // transfer base token to taker
            baseToken.transfer(msg.sender, filledAmt);
        }
    }

    // taker is sell
    function fillBidOrders(
        uint64[] calldata idList,
        uint96[] calldata amtList,
        uint256 maxAmt,
        uint256 minAmt // base amount
    ) public payable {
        if (idList.length != amtList.length) {
            revert InvalidParam();
        }

        uint256 filledAmt = 0; // accumulate base amount
        uint256 filledVol = 0; // accumulate quote amount
        uint256 filledFee = 0; // accumulate fee, by quote

        for (uint i = 0; i < idList.length; ) {
            uint64 id = idList[i];
            uint96 filled = amtList[i];
            Order storage order = bidOrders[id];
            uint96 amount = order.amount;
            uint160 price = order.price;

            if (amount == 0) {
                // order NOT exist or filled
                unchecked {
                    ++i;
                }
                continue;
            }
            uint96 vol = calcQuoteAmount(filled, price); // quoteVol = filled * price
            if (amount < vol) {
                vol = amount;
                filled = calcBaseAmount(vol, price);
            }
            if (maxAmt > 0 && maxAmt - filledAmt < filled) {
                unchecked {
                    filled = uint96(maxAmt - filledAmt);
                }
                vol = calcQuoteAmount(filled, price);
            }
            (uint96 totalFee, uint96 makerFee) = calcFee(vol);
            Order storage revOrder = askOrders[id];
            // base token reversed
            revOrder.amount += filled;
            unchecked {
                order.amount -= vol - makerFee;
                filledAmt += filled;
                filledVol += vol;
                filledFee += totalFee;
            }
            if (maxAmt > 0 && filledAmt >= maxAmt) {
                break;
            }
            unchecked {
                ++i;
            }
        }

        if (minAmt > 0 && filledAmt < minAmt) {
            revert NotEnoughToFill();
        }
        if (filledVol > 0) {
            unchecked {
                filledVol -= filledFee;
            }
            // transfer quote token to taker
            quoteToken.transfer(msg.sender, filledVol);
            // transfer base token from taker
            if (baseToken.isNative()) {
                if (msg.value < filledAmt) revert NotEnoughQuoteToken();
                if (msg.value > filledAmt) {
                    baseToken.transfer(msg.sender, msg.value - filledAmt);
                }
            } else {
                IERC20Minimal(Currency.unwrap(baseToken)).safeTransferFrom(
                    msg.sender,
                    address(this),
                    filledAmt
                );
            }
        }
    }

    // cancel grid order will cancel both ask order and bid order
    function cancelGridOrders(uint64[] calldata idList) public {
        uint96 baseAmt = 0;
        uint96 quoteAmt = 0;
        for (uint i = 0; i < idList.length; ) {
            uint64 id = idList[i];

            Order storage askOrder = askOrders[id];
            Order storage bidOrder = bidOrders[id];
            uint64 gridId = uint64(askOrder.gridId);
            if (gridId == 0) {
                // invalid order
                revert InvalidGridId();
            }
            GridConfig storage conf = gridConfigs[gridId];
            if (msg.sender != conf.owner) {
                revert NotGridOrder();
            }

            baseAmt += askOrder.amount;
            quoteAmt += bidOrder.amount;
            emit CancelGridOrder(gridId, id, askOrder.amount, bidOrder.amount);

            delete askOrders[id];
            delete bidOrders[id];

            unchecked {
                ++i;
                conf.orders--;
            }
            if (conf.orders == 0) {
                delete gridConfigs[uint64(gridId)];
            }
        }
        if (baseAmt > 0) {
            // transfer
            baseToken.transfer(msg.sender, baseAmt);
        }
        if (quoteAmt > 0) {
            // transfer
            quoteToken.transfer(msg.sender, quoteAmt);
        }
    }

    /// @inheritdoc IPair
    function setFeeProtocol(uint8 _feeProtocol) external override {
        require(msg.sender == IFactory(factory).owner());

        require(
            _feeProtocol == 0 || (_feeProtocol >= 4 && _feeProtocol <= 10));
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
