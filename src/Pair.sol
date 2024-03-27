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
        uint96 revAmount;
        // grid id, or address if limit order
        uint64 gridId;
        // order id
        uint64 orderId;
        bool canceled;
    }

    mapping(uint64 orderId => Order) public bidOrders;
    mapping(uint64 orderId => Order) public askOrders;

    struct GridConfig {
        address owner;
        uint128 profits; // quote token
        uint32 orders;
        bool compound;
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
    }

    function isAskGridOrder(uint64 orderId) public returns (bool) {
        return orderId & AskOderMask > 0;
    }

    function placeGridOrders(GridOrderParam calldata params) public payable {
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
            askOrders[askOrderId] = Order({
                gridId: gridId,
                orderId: askOrderId,
                amount: uint96(params.baseAmount),
                revAmount: 0,
                price: uint160(params.sellPrice0),
                canceled: false
            });
            IERC20Minimal(Currency.unwrap(baseToken)).safeTransferFrom(
                msg.sender,
                address(this),
                params.asks * params.baseAmount
            );
        }

        if (params.bids > 0) {
            uint256 buyPrice0 = params.buyPrice0;
            uint256 buyGap = params.buyGap;
            uint256 amt0;
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
                    if (i == 0) {
                        amt0 = amt;
                    }

                    quoteAmt += amt;
                    ++i;
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
            bidOrders[bidOrderId] = Order({
                gridId: gridId,
                orderId: bidOrderId,
                amount: uint96(amt0),
                price: uint160(buyPrice0),
                revAmount: 0,
                canceled: false
            });
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
            compound: params.compound
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

    function calcQuoteAmount2(
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
        return (amt);
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
    ) public pure returns (uint96) {
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
        return uint96(amt);
    }

    // amount is always quote amount
    function calcFee(uint256 amount) public returns (uint96, uint96) {
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
            uint256 vol = calcQuoteAmount(filled, uint256(order.price)) + 1; // quoteVol = filled * price
            (uint96 totalFee, uint96 lpFee) = calcFee(vol);

            emit FilledOrder(order.orderId, uint96(vol), totalFee, lpFee);

            Order storage bidOrder = bidOrders[id];
            // all sell and fee go to reversed grid order
            bidOrder.amount += uint96(vol + lpFee);

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
            uint256 filled = amtList[i];
            Order storage order = bidOrders[id];
            uint96 amount = order.amount;
            uint256 price = order.price;

            if (amount == 0) {
                // order NOT exist or filled
                unchecked {
                    ++i;
                }
                continue;
            }
            uint256 vol = calcQuoteAmount(filled, price); // quoteVol = filled * price
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
            revOrder.amount += uint96(filled);
            unchecked {
                order.amount -= uint96(vol - makerFee);
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

    function getGridOrders(
        uint64[] calldata idList
    ) public returns (Order[] memory) {
        Order[] memory orderList = new Order[](idList.length);

        for (uint i = 0; i < idList.length; i++) {}
        return orderList;
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
