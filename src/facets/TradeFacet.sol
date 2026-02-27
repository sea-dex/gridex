// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "../interfaces/IGridOrder.sol";
import {IGridCallback} from "../interfaces/IGridCallback.sol";
import {IOrderErrors} from "../interfaces/IOrderErrors.sol";
import {IOrderEvents} from "../interfaces/IOrderEvents.sol";
import {IProtocolErrors} from "../interfaces/IProtocolErrors.sol";
import {IPair} from "../interfaces/IPair.sol";
import {IWETH} from "../interfaces/IWETH.sol";

import {SafeCast} from "../libraries/SafeCast.sol";
import {Currency, CurrencyLibrary} from "../libraries/Currency.sol";
import {GridOrder} from "../libraries/GridOrder.sol";
import {GridExStorage} from "../libraries/GridExStorage.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/// @title TradeFacet
/// @author GridEx Protocol
/// @notice Core trading logic: place + fill grid orders
/// @dev Delegatecalled by GridExRouter. All state access via GridExStorage.layout().
///      No modifiers — guards (pause, reentrancy) are applied at the Router level.
contract TradeFacet is IOrderEvents {
    using SafeCast for *;
    using CurrencyLibrary for Currency;
    using GridOrder for GridOrder.GridState;
    using SafeTransferLib for ERC20;

    /// @notice Emitted when a quote token's priority is set or updated
    event QuotableTokenUpdated(Currency quote, uint256 priority);

    /// @notice Emitted when grid profits are withdrawn
    event WithdrawProfit(uint48 gridId, Currency quote, address to, uint256 amt);

    /// @notice Emitted when an ETH refund attempt fails
    event RefundFailed(address indexed to, uint256 amount);

    error NotEnough();
    error ETHTransferFailed();
    error NotWETH();

    // ─── Pair helpers ────────────────────────────────────────────────

    function _getOrCreatePair(Currency base, Currency quote) internal returns (IPair.Pair memory) {
        GridExStorage.Layout storage l = GridExStorage.layout();
        IPair.Pair memory pair = l.getPair[base][quote];
        if (pair.pairId > 0) {
            return pair;
        }

        if (base == quote) {
            revert IProtocolErrors.TokenOrderInvalid();
        }

        if (l.quotableTokens[quote] == 0) {
            revert IPair.InvalidQuote();
        }
        if (l.quotableTokens[base] > l.quotableTokens[quote]) {
            revert IPair.InvalidQuote();
        }
        if (l.quotableTokens[base] == l.quotableTokens[quote]) {
            if (!(base < quote)) {
                revert IProtocolErrors.TokenOrderInvalid();
            }
        }

        uint64 pairId = l.nextPairId++;
        pair.base = base;
        pair.quote = quote;
        pair.pairId = pairId;

        l.getPair[base][quote] = pair;
        l.getPairById[pairId] = pair;

        emit IPair.PairCreated(base, quote, pairId);

        return pair;
    }

    // ─── Asset settlement helpers ────────────────────────────────────

    // forge-lint: disable-next-line(mixed-case-function)
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        if (!success) revert ETHTransferFailed();
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function _tryPaybackETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        if (!success) {
            emit RefundFailed(to, value);
        }
    }

    function _settleAssetWith(
        Currency inToken,
        Currency outToken,
        address addr,
        uint256 inAmt,
        uint256 outAmt,
        uint256 paid,
        uint32 flag
    ) internal {
        address weth = GridExStorage.layout().weth;
        if (flag == 0) {
            ERC20(Currency.unwrap(inToken)).safeTransferFrom(addr, address(this), inAmt);
            outToken.transfer(addr, outAmt);
        } else {
            if (flag & 0x01 > 0) {
                if (Currency.unwrap(inToken) != weth) revert NotWETH();
                if (paid < inAmt) revert IProtocolErrors.InsufficientETH();
                IWETH(weth).deposit{value: inAmt}();
                if (paid > inAmt) {
                    _tryPaybackETH(addr, paid - inAmt);
                }
            } else {
                ERC20(Currency.unwrap(inToken)).safeTransferFrom(addr, address(this), inAmt);
            }

            if (flag & 0x02 > 0) {
                if (Currency.unwrap(outToken) != weth) revert NotWETH();
                IWETH(weth).withdraw(outAmt);
                _safeTransferETH(addr, outAmt);
            } else {
                outToken.transfer(addr, outAmt);
            }
        }
    }

    function _transferTokenFrom(Currency token, address addr, uint256 amount) internal {
        ERC20(Currency.unwrap(token)).safeTransferFrom(addr, address(this), amount);
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function _transferETHFrom(address from, uint128 amt, uint128 paid) internal {
        address weth = GridExStorage.layout().weth;
        IWETH(weth).deposit{value: amt}();
        if (paid > amt) {
            _safeTransferETH(from, paid - amt);
        }
    }

    function _incProtocolProfits(Currency quote, uint128 profit) internal {
        address v = GridExStorage.layout().vault;
        quote.transfer(v, profit);
    }

    // ─── Place orders ────────────────────────────────────────────────

    /// @notice Place grid orders with ETH as either base or quote token
    /// @dev Either base or quote must be address(0) representing ETH
    /// @param base The base token (address(0) for ETH)
    /// @param quote The quote token (address(0) for ETH)
    /// @param param The grid order parameters
    // forge-lint: disable-next-line(mixed-case-function)
    function placeETHGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param)
        external
        payable
    {
        if (msg.value > type(uint128).max) revert IProtocolErrors.InsufficientETH();
        GridExStorage.Layout storage l = GridExStorage.layout();
        // forge-lint: disable-next-line(mixed-case-variable)
        bool baseIsETH = false;
        if (base.isAddressZero()) {
            baseIsETH = true;
            base = Currency.wrap(l.weth);
        } else if (quote.isAddressZero()) {
            quote = Currency.wrap(l.weth);
        } else {
            revert IOrderErrors.InvalidParam();
        }

        (, uint128 baseAmt, uint128 quoteAmt) = _placeGridOrders(msg.sender, base, quote, param);

        if (baseIsETH) {
            if (msg.value < baseAmt) revert IProtocolErrors.InsufficientETH();
            _transferETHFrom(msg.sender, baseAmt, uint128(msg.value));
            _transferTokenFrom(quote, msg.sender, quoteAmt);
        } else {
            if (msg.value < quoteAmt) revert IProtocolErrors.InsufficientETH();
            _transferETHFrom(msg.sender, quoteAmt, uint128(msg.value));
            _transferTokenFrom(base, msg.sender, baseAmt);
        }
    }

    /// @notice Place grid orders with ERC20 tokens
    /// @param base The base token address
    /// @param quote The quote token address
    /// @param param The grid order parameters
    function placeGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param) external {
        if (base.isAddressZero() || quote.isAddressZero()) {
            revert IOrderErrors.InvalidParam();
        }

        (IPair.Pair memory pair, uint128 baseAmt, uint128 quoteAmt) = _placeGridOrders(msg.sender, base, quote, param);

        if (baseAmt > 0) {
            _transferTokenFrom(pair.base, msg.sender, baseAmt);
        }
        if (quoteAmt > 0) {
            _transferTokenFrom(pair.quote, msg.sender, quoteAmt);
        }
    }

    function _placeGridOrders(address maker, Currency base, Currency quote, IGridOrder.GridOrderParam calldata param)
        private
        returns (IPair.Pair memory pair, uint128 baseAmt, uint128 quoteAmt)
    {
        GridExStorage.Layout storage l = GridExStorage.layout();

        if (param.askOrderCount > 0) {
            if (!l.whitelistedStrategies[address(param.askStrategy)]) {
                revert IOrderErrors.StrategyNotWhitelisted();
            }
        }
        if (param.bidOrderCount > 0) {
            if (!l.whitelistedStrategies[address(param.bidStrategy)]) {
                revert IOrderErrors.StrategyNotWhitelisted();
            }
        }

        pair = _getOrCreatePair(base, quote);

        // uint256 startAskOrderId;
        // uint256 startBidOrderId;
        uint48 gridId;
        (gridId, baseAmt, quoteAmt) = l.gridState.placeGridOrder(pair.pairId, maker, param);

        emit GridOrderCreated(
            maker,
            pair.pairId,
            param.baseAmount,
            gridId,
            // startAskOrderId,
            // startBidOrderId,
            param.askOrderCount,
            param.bidOrderCount,
            param.fee,
            param.compound,
            param.oneshot
        );
    }

    // ─── Fill ask orders ─────────────────────────────────────────────

    struct AccFilled {
        uint128 amt;
        uint128 vol;
        uint128 protocolFee;
    }

    /// @notice Fill a single ask grid order (buy base token)
    /// @param gridOrderId The combined grid ID and order ID
    /// @param amt The base amount to buy
    /// @param minAmt The minimum base amount to accept (slippage protection)
    /// @param data Callback data (if non-empty, triggers flash-swap callback)
    /// @param flag Bit flags: 0 = ERC20 only, 1 = quote is ETH, 2 = base is ETH
    function fillAskOrder(uint64 gridOrderId, uint128 amt, uint128 minAmt, bytes calldata data, uint32 flag)
        external
        payable
    {
        GridExStorage.Layout storage l = GridExStorage.layout();
        IGridOrder.OrderFillResult memory result = l.gridState.fillAskOrder(gridOrderId, amt);

        if (minAmt > 0 && result.filledAmt < minAmt) {
            revert IOrderErrors.NotEnoughToFill();
        }

        emit FilledOrder(
            msg.sender, gridOrderId, result.filledAmt, result.filledVol, result.orderAmt, result.orderRevAmt, true
        );

        IPair.Pair memory pair = l.getPairById[result.pairId];
        uint128 inAmt = result.filledVol + result.lpFee + result.protocolFee;
        if (data.length > 0) {
            _incProtocolProfits(pair.quote, result.protocolFee);
            uint256 balanceBefore = pair.quote.balanceOfSelf();

            pair.base.transfer(msg.sender, result.filledAmt);
            IGridCallback(msg.sender)
                .gridFillCallback(
                    Currency.unwrap(pair.quote), Currency.unwrap(pair.base), inAmt, result.filledAmt, data
                );
            if (balanceBefore + inAmt > pair.quote.balanceOfSelf()) {
                revert IProtocolErrors.CallbackInsufficientInput();
            }
        } else {
            _settleAssetWith(pair.quote, pair.base, msg.sender, inAmt, result.filledAmt, msg.value, flag);
            _incProtocolProfits(pair.quote, result.protocolFee);
        }
    }

    /// @notice Fill multiple ask orders in a single transaction
    /// @param pairId The trading pair ID
    /// @param idList Array of grid order IDs to fill
    /// @param amtList Array of base amounts to fill for each order
    /// @param maxAmt Maximum total base amount to buy (0 = no limit)
    /// @param minAmt Minimum total base amount to accept
    /// @param data Callback data for flash-swap
    /// @param flag Bit flags for ETH handling
    function fillAskOrders(
        uint64 pairId,
        uint64[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt,
        uint128 minAmt,
        bytes calldata data,
        uint32 flag
    ) external payable {
        if (idList.length != amtList.length) {
            revert IOrderErrors.InvalidParam();
        }

        GridExStorage.Layout storage l = GridExStorage.layout();
        AccFilled memory filled;
        for (uint256 i; i < idList.length;) {
            uint64 gridOrderId = idList[i];
            uint128 amt = amtList[i];

            if (maxAmt > 0 && maxAmt < filled.amt + amt) {
                amt = maxAmt - filled.amt;
            }

            IGridOrder.OrderFillResult memory result = l.gridState.fillAskOrder(gridOrderId, amt);
            if (result.pairId != pairId) {
                revert IProtocolErrors.PairIdMismatch();
            }

            emit FilledOrder(
                msg.sender, gridOrderId, result.filledAmt, result.filledVol, result.orderAmt, result.orderRevAmt, true
            );

            filled.amt += result.filledAmt;
            filled.vol += result.filledVol + result.lpFee + result.protocolFee;
            filled.protocolFee += result.protocolFee;

            if (maxAmt > 0 && filled.amt >= maxAmt) {
                break;
            }
            unchecked {
                ++i;
            }
        }

        if (minAmt > 0 && filled.amt < minAmt) {
            revert IOrderErrors.NotEnoughToFill();
        }

        IPair.Pair memory pair = l.getPairById[pairId];
        Currency quote = pair.quote;
        if (data.length > 0) {
            _incProtocolProfits(quote, filled.protocolFee);
            uint256 balanceBefore = pair.quote.balanceOfSelf();
            pair.base.transfer(msg.sender, filled.amt);
            IGridCallback(msg.sender)
                .gridFillCallback(Currency.unwrap(pair.quote), Currency.unwrap(pair.base), filled.vol, filled.amt, data);
            if (balanceBefore + filled.vol > pair.quote.balanceOfSelf()) {
                revert IProtocolErrors.CallbackInsufficientInput();
            }
        } else {
            _settleAssetWith(quote, pair.base, msg.sender, filled.vol, filled.amt, msg.value, flag);
            _incProtocolProfits(quote, filled.protocolFee);
        }
    }

    // ─── Fill bid orders ─────────────────────────────────────────────

    /// @notice Fill a single bid grid order (sell base token)
    /// @param gridOrderId The combined grid ID and order ID (64 bits)
    /// @param amt The base amount to sell
    /// @param minAmt The minimum base amount to accept (slippage protection)
    /// @param data Callback data (if non-empty, triggers flash-swap callback)
    /// @param flag Bit flags: 0 = ERC20 only, 1 = base is ETH, 2 = quote is ETH
    function fillBidOrder(uint64 gridOrderId, uint128 amt, uint128 minAmt, bytes calldata data, uint32 flag)
        external
        payable
    {
        GridExStorage.Layout storage l = GridExStorage.layout();
        IGridOrder.OrderFillResult memory result = l.gridState.fillBidOrder(gridOrderId, amt);

        if (minAmt > 0 && result.filledAmt < minAmt) {
            revert IOrderErrors.NotEnoughToFill();
        }

        emit FilledOrder(
            msg.sender, gridOrderId, result.filledAmt, result.filledVol, result.orderAmt, result.orderRevAmt, false
        );

        IPair.Pair memory pair = l.getPairById[result.pairId];
        uint128 outAmt = result.filledVol - result.lpFee - result.protocolFee;

        if (data.length > 0) {
            _incProtocolProfits(pair.quote, result.protocolFee);
            pair.quote.transfer(msg.sender, outAmt);
            uint256 balanceBefore = pair.base.balanceOfSelf();
            IGridCallback(msg.sender)
                .gridFillCallback(
                    Currency.unwrap(pair.base), Currency.unwrap(pair.quote), result.filledAmt, outAmt, data
                );
            if (balanceBefore + result.filledAmt > pair.base.balanceOfSelf()) {
                revert IProtocolErrors.CallbackInsufficientInput();
            }
        } else {
            _settleAssetWith(pair.base, pair.quote, msg.sender, result.filledAmt, outAmt, msg.value, flag);
            _incProtocolProfits(pair.quote, result.protocolFee);
        }
    }

    /// @notice Fill multiple bid orders in a single transaction
    /// @param pairId The trading pair ID
    /// @param idList Array of grid order IDs to fill
    /// @param amtList Array of base amounts to fill for each order
    /// @param maxAmt Maximum total base amount to sell (0 = no limit)
    /// @param minAmt Minimum total base amount to accept
    /// @param data Callback data for flash-swap
    /// @param flag Bit flags for ETH handling
    function fillBidOrders(
        uint64 pairId,
        uint64[] calldata idList,
        uint128[] calldata amtList,
        uint128 maxAmt,
        uint128 minAmt,
        bytes calldata data,
        uint32 flag
    ) external payable {
        if (idList.length != amtList.length) {
            revert IOrderErrors.InvalidParam();
        }

        GridExStorage.Layout storage l = GridExStorage.layout();
        address taker = msg.sender;
        uint128 filledAmt = 0;
        uint128 filledVol = 0;
        uint128 protocolFee = 0;

        for (uint256 i; i < idList.length;) {
            uint64 gridOrderId = idList[i];
            uint128 amt = amtList[i];

            if (maxAmt > 0 && maxAmt - filledAmt < amt) {
                amt = maxAmt - filledAmt;
            }

            IGridOrder.OrderFillResult memory result = l.gridState.fillBidOrder(gridOrderId, amt);

            if (result.pairId != pairId) {
                revert IProtocolErrors.PairIdMismatch();
            }

            if (result.filledAmt == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }

            emit FilledOrder(
                msg.sender, gridOrderId, result.filledAmt, result.filledVol, result.orderAmt, result.orderRevAmt, false
            );

            filledAmt += result.filledAmt;
            filledVol += result.filledVol - result.lpFee - result.protocolFee;
            protocolFee += result.protocolFee;

            if (maxAmt > 0 && filledAmt >= maxAmt) {
                break;
            }
            unchecked {
                ++i;
            }
        }

        if (minAmt > 0 && filledAmt < minAmt) {
            revert IOrderErrors.NotEnoughToFill();
        }

        IPair.Pair memory pair = l.getPairById[pairId];
        if (data.length > 0) {
            _incProtocolProfits(pair.quote, protocolFee);
            pair.quote.transfer(msg.sender, filledVol);
            uint256 balanceBefore = pair.base.balanceOfSelf();
            IGridCallback(msg.sender)
                .gridFillCallback(Currency.unwrap(pair.base), Currency.unwrap(pair.quote), filledAmt, filledVol, data);
            if (balanceBefore + filledAmt > pair.base.balanceOfSelf()) {
                revert IProtocolErrors.CallbackInsufficientInput();
            }
        } else {
            _settleAssetWith(pair.base, pair.quote, taker, filledAmt, filledVol, msg.value, flag);
            _incProtocolProfits(pair.quote, protocolFee);
        }
    }
}
