// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {IGridOrder} from "./interfaces/IGridOrder.sol";
import {IGridEx} from "./interfaces/IGridEx.sol";
import {IGridCallback} from "./interfaces/IGridCallback.sol";
import {IOrderErrors} from "./interfaces/IOrderErrors.sol";
import {IOrderEvents} from "./interfaces/IOrderEvents.sol";
import {IProtocolErrors} from "./interfaces/IProtocolErrors.sol";

import {Pair} from "./Pair.sol";
import {AssetSettle} from "./AssetSettle.sol";

import {SafeCast} from "./libraries/SafeCast.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";
import {GridOrder} from "./libraries/GridOrder.sol";
import {ProtocolConstants} from "./libraries/ProtocolConstants.sol";

import {Owned} from "solmate/auth/Owned.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {Pausable} from "./utils/Pausable.sol";

/// @title GridEx
/// @author GridEx Protocol
/// @notice Main contract for the GridEx decentralized grid trading protocol
/// @dev Implements grid order placement, filling, and cancellation with support for ETH and ERC20 tokens
contract GridEx is IGridEx, AssetSettle, Pair, Owned, ReentrancyGuard, Pausable {
    using SafeCast for *;
    using CurrencyLibrary for Currency;
    using GridOrder for GridOrder.GridState;

    /// @notice The vault address that receives protocol fees
    address public vault;

    /// @notice Flag to track if the contract has been initialized
    bool public initialized;

    /// @dev Internal state for managing grid orders
    GridOrder.GridState internal _gridState;

    /// @notice Mapping of whitelisted strategy contracts
    /// @dev Only whitelisted strategies can be used for grid orders
    mapping(address => bool) public whitelistedStrategies;

    /// @notice Creates a new GridEx contract
    /// @dev For CREATE2 deterministic deployment, owner and vault are passed in constructor
    /// @param _owner The address that will own this contract
    /// @param _vault The vault address for protocol fees
    constructor(address _owner, address _vault) Owned(_owner) {
        require(_owner != address(0), "invalid owner");
        require(_vault != address(0), "invalid vault");

        vault = _vault;
        _gridState.initialize();
    }

    /// @notice Initialize the contract with WETH and USD addresses
    /// @dev This function can only be called once by the owner
    /// @param _weth The WETH contract address
    /// @param _usd The USD stablecoin address (highest priority quote token)
    function initialize(address _weth, address _usd) external onlyOwner {
        require(!initialized, "already initialized");
        require(_weth != address(0), "invalid weth");
        require(_usd != address(0), "invalid usd");

        initialized = true;

        // usd is the most priority quote token
        quotableTokens[Currency.wrap(_usd)] = ProtocolConstants.QUOTE_PRIORITY_USD;
        // quotableTokens[Currency.wrap(address(0))] = ProtocolConstants.QUOTE_PRIORITY_WETH;
        quotableTokens[Currency.wrap(_weth)] = ProtocolConstants.QUOTE_PRIORITY_WETH;
        WETH = _weth;
    }

    /// @notice Allows the contract to receive ETH
    receive() external payable {}

    /// @inheritdoc IGridEx
    function getGridOrder(uint256 id) public view override returns (IGridOrder.OrderInfo memory) {
        return _gridState.getOrderInfo(id, false);
    }

    /// @inheritdoc IGridEx
    function getGridOrders(uint256[] calldata idList) public view override returns (IGridOrder.OrderInfo[] memory) {
        uint256 len = idList.length;
        IGridOrder.OrderInfo[] memory orderList = new IGridOrder.OrderInfo[](len);

        for (uint256 i; i < len;) {
            orderList[i] = _gridState.getOrderInfo(idList[i], false);
            unchecked {
                ++i;
            }
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

    /// @notice Place grid orders with ETH as either base or quote token
    /// @dev Either base or quote must be address(0) representing ETH
    /// @param base The base token (address(0) for ETH)
    /// @param quote The quote token (address(0) for ETH)
    /// @param param The grid order parameters
    // forge-lint: disable-next-line(mixed-case-function)
    function placeETHGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param)
        public
        payable
        whenNotPaused
    {
        // forge-lint: disable-next-line(mixed-case-variable)
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
            require(msg.value >= baseAmt, "GridEx: Insufficient ETH sent");
            AssetSettle.transferETHFrom(msg.sender, baseAmt, uint128(msg.value));
            AssetSettle.transferTokenFrom(quote, msg.sender, quoteAmt);
        } else {
            require(msg.value >= quoteAmt, "GridEx: Insufficient ETH sent");
            AssetSettle.transferETHFrom(msg.sender, quoteAmt, uint128(msg.value));
            AssetSettle.transferTokenFrom(base, msg.sender, baseAmt);
        }
    }

    /// @inheritdoc IGridEx
    function placeGridOrders(Currency base, Currency quote, IGridOrder.GridOrderParam calldata param)
        public
        override
        whenNotPaused
    {
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

    /// @notice Internal function to place grid orders
    /// @param maker The order maker address
    /// @param base The base token
    /// @param quote The quote token
    /// @param param The grid order parameters
    /// @return pair The trading pair info
    /// @return baseAmt The total base token amount required
    /// @return quoteAmt The total quote token amount required
    function _placeGridOrders(address maker, Currency base, Currency quote, IGridOrder.GridOrderParam calldata param)
        private
        returns (Pair memory pair, uint128 baseAmt, uint128 quoteAmt)
    {
        // Validate that strategies are whitelisted
        if (param.askOrderCount > 0) {
            if (!whitelistedStrategies[address(param.askStrategy)]) {
                revert IOrderErrors.StrategyNotWhitelisted();
            }
        }
        if (param.bidOrderCount > 0) {
            if (!whitelistedStrategies[address(param.bidStrategy)]) {
                revert IOrderErrors.StrategyNotWhitelisted();
            }
        }

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

    /// @notice Transfers protocol profits to the vault
    /// @dev This function is called internally when protocol fees are collected from trades.
    ///      The profit is transferred directly to the vault address for later withdrawal by the protocol owner.
    /// @param quote The quote currency (token) in which the profit is denominated
    /// @param profit The profit amount to transfer to the vault
    function incProtocolProfits(Currency quote, uint128 profit) private {
        quote.transfer(vault, profit);
    }

    /// @inheritdoc IGridEx
    function fillAskOrder(
        uint256 gridOrderId,
        uint128 amt, // base amount
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    )
        public
        payable
        override
        nonReentrant
        whenNotPaused
    {
        IGridOrder.OrderFillResult memory result = _gridState.fillAskOrder(gridOrderId, amt);

        if (minAmt > 0 && result.filledAmt < minAmt) {
            revert IOrderErrors.NotEnoughToFill();
        }

        emit IOrderEvents.FilledOrder(
            msg.sender, gridOrderId, result.filledAmt, result.filledVol, result.orderAmt, result.orderRevAmt, true
        );

        Pair memory pair = getPairById[result.pairId];
        uint128 inAmt = result.filledVol + result.lpFee + result.protocolFee;
        if (data.length > 0) {
            incProtocolProfits(pair.quote, result.protocolFee);
            uint256 balanceBefore = pair.quote.balanceOfSelf();

            // always transfer ERC20 to msg.sender
            pair.base.transfer(msg.sender, result.filledAmt);
            IGridCallback(msg.sender)
                .gridFillCallback(
                    Currency.unwrap(pair.quote), Currency.unwrap(pair.base), inAmt, result.filledAmt, data
                );
            if (balanceBefore + inAmt > pair.quote.balanceOfSelf()) {
                revert IProtocolErrors.CallbackInsufficientInput();
            }
        } else {
            AssetSettle.settleAssetWith(pair.quote, pair.base, msg.sender, inAmt, result.filledAmt, msg.value, flag);
            incProtocolProfits(pair.quote, result.protocolFee);
        }
    }

    /// @dev Struct to accumulate filled amounts across multiple orders
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
    ) public payable override nonReentrant whenNotPaused {
        if (idList.length != amtList.length) {
            revert IOrderErrors.InvalidParam();
        }

        // address taker = msg.sender;
        AccFilled memory filled;
        for (uint256 i; i < idList.length;) {
            uint256 gridOrderId = idList[i];
            uint128 amt = amtList[i];

            if (maxAmt > 0 && maxAmt < filled.amt + amt) {
                amt = maxAmt - filled.amt;
            }

            IGridOrder.OrderFillResult memory result = _gridState.fillAskOrder(gridOrderId, amt);
            if (result.pairId != pairId) {
                revert IProtocolErrors.PairIdMismatch();
            }

            emit IOrderEvents.FilledOrder(
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

        Pair memory pair = getPairById[pairId];
        Currency quote = pair.quote;
        if (data.length > 0) {
            incProtocolProfits(quote, filled.protocolFee);
            uint256 balanceBefore = pair.quote.balanceOfSelf();
            // always transfer ERC20 to msg.sender
            pair.base.transfer(msg.sender, filled.amt);
            IGridCallback(msg.sender)
                .gridFillCallback(Currency.unwrap(pair.quote), Currency.unwrap(pair.base), filled.vol, filled.amt, data);
            if (balanceBefore + filled.vol > pair.quote.balanceOfSelf()) {
                revert IProtocolErrors.CallbackInsufficientInput();
            }
        } else {
            AssetSettle.settleAssetWith(quote, pair.base, msg.sender, filled.vol, filled.amt, msg.value, flag);
            incProtocolProfits(quote, filled.protocolFee);
        }
    }

    /// @inheritdoc IGridEx
    function fillBidOrder(
        uint256 gridOrderId,
        uint128 amt,
        uint128 minAmt, // base amount
        bytes calldata data,
        uint32 flag
    )
        public
        payable
        override
        nonReentrant
        whenNotPaused
    {
        IGridOrder.OrderFillResult memory result = _gridState.fillBidOrder(gridOrderId, amt);

        if (minAmt > 0 && result.filledAmt < minAmt) {
            revert IOrderErrors.NotEnoughToFill();
        }

        emit IOrderEvents.FilledOrder(
            msg.sender, gridOrderId, result.filledAmt, result.filledVol, result.orderAmt, result.orderRevAmt, false
        );

        Pair memory pair = getPairById[result.pairId];
        uint128 outAmt = result.filledVol - result.lpFee - result.protocolFee;

        if (data.length > 0) {
            incProtocolProfits(pair.quote, result.protocolFee);
            // always transfer ERC20 to msg.sender
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
            AssetSettle.settleAssetWith(pair.base, pair.quote, msg.sender, result.filledAmt, outAmt, msg.value, flag);
            incProtocolProfits(pair.quote, result.protocolFee);
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
    ) public payable override nonReentrant whenNotPaused {
        if (idList.length != amtList.length) {
            revert IOrderErrors.InvalidParam();
        }

        address taker = msg.sender;
        uint128 filledAmt = 0; // accumulate base amount
        uint128 filledVol = 0; // accumulate quote amount
        uint128 protocolFee = 0; // accumulate protocol fees

        for (uint256 i; i < idList.length;) {
            uint256 gridOrderId = idList[i];
            uint128 amt = amtList[i];

            if (maxAmt > 0 && maxAmt - filledAmt < amt) {
                amt = maxAmt - filledAmt;
            }

            IGridOrder.OrderFillResult memory result = _gridState.fillBidOrder(gridOrderId, amt);

            if (result.pairId != pairId) {
                revert IProtocolErrors.PairIdMismatch();
            }

            // Skip dust fills that produced zero quote amount
            if (result.filledAmt == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }

            emit IOrderEvents.FilledOrder(
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

        Pair memory pair = getPairById[pairId];
        if (data.length > 0) {
            incProtocolProfits(pair.quote, protocolFee);
            // always transfer ERC20 to msg.sender
            pair.quote.transfer(msg.sender, filledVol);
            uint256 balanceBefore = pair.base.balanceOfSelf();
            IGridCallback(msg.sender)
                .gridFillCallback(Currency.unwrap(pair.base), Currency.unwrap(pair.quote), filledAmt, filledVol, data);
            if (balanceBefore + filledAmt > pair.base.balanceOfSelf()) {
                revert IProtocolErrors.CallbackInsufficientInput();
            }
        } else {
            AssetSettle.settleAssetWith(pair.base, pair.quote, taker, filledAmt, filledVol, msg.value, flag);
            incProtocolProfits(pair.quote, protocolFee);
        }
    }

    /// @inheritdoc IGridEx
    function withdrawGridProfits(uint128 gridId, uint256 amt, address to, uint32 flag) public override nonReentrant {
        IGridOrder.GridConfig memory conf = _gridState.gridConfigs[gridId];
        if (conf.owner != msg.sender) {
            revert IOrderErrors.NotGridOwer();
        }

        if (amt == 0) {
            amt = conf.profits;
        } else if (conf.profits < amt) {
            amt = conf.profits;
        }

        if (amt == 0) {
            revert IOrderErrors.NoProfits();
        }

        if (amt >= 1 << 128) {
            revert IOrderErrors.ExceedMaxAmount();
        }

        Pair memory pair = getPairById[conf.pairId];

        // casting to 'uint128' is safe because amt < 1<<128
        // forge-lint: disable-next-line(unsafe-typecast)
        _gridState.gridConfigs[gridId].profits = conf.profits - uint128(amt);

        // casting to 'uint128' is safe because amt < 1<<128
        // forge-lint: disable-next-line(unsafe-typecast)
        AssetSettle.transferAssetTo(pair.quote, to, uint128(amt), flag);

        emit WithdrawProfit(gridId, pair.quote, to, amt);
    }

    /// @inheritdoc IGridEx
    function modifyGridFee(uint128 gridId, uint32 fee) public override {
        _gridState.modifyGridFee(msg.sender, gridId, fee);
    }

    /// @inheritdoc IGridEx
    function cancelGrid(address recipient, uint128 gridId, uint32 flag) public override nonReentrant {
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

    /// @notice Cancel a range of consecutive grid orders
    /// @param recipient The address to receive the refunded tokens
    /// @param startGridOrderId The first grid order ID to cancel
    /// @param howmany The number of consecutive orders to cancel
    /// @param flag Bit flags for ETH conversion: 0x1 = base to ETH, 0x2 = quote to ETH
    function cancelGridOrders(address recipient, uint256 startGridOrderId, uint32 howmany, uint32 flag)
        public
        override
    {
        uint256[] memory idList = new uint256[](howmany);
        (uint128 gridId,) = GridOrder.extractGridIdOrderId(startGridOrderId);
        for (uint256 i; i < howmany;) {
            idList[i] = startGridOrderId + i;
            unchecked {
                ++i;
            }
        }

        cancelGridOrders(gridId, recipient, idList, flag);
    }

    /// @inheritdoc IGridEx
    function cancelGridOrders(uint128 gridId, address recipient, uint256[] memory idList, uint32 flag)
        public
        override
        nonReentrant
    {
        (uint64 pairId, uint256 baseAmt, uint256 quoteAmt) = _gridState.cancelGridOrders(msg.sender, gridId, idList);

        Pair memory pair = getPairById[pairId];
        if (baseAmt > 0) {
            // transfer base
            AssetSettle.transferAssetTo(pair.base, recipient, baseAmt, flag & 0x1);
        }
        if (quoteAmt > 0) {
            // transfer quote
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

    /// @notice Rescue stuck ETH (e.g., from failed refunds)
    /// @dev Only callable by the owner
    /// @param to The address to receive the ETH
    /// @param amount The amount of ETH to withdraw
    function rescueEth(address to, uint256 amount) external onlyOwner {
        (bool success,) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /// @notice Set the protocol fee for oneshot orders
    /// @dev Only callable by the owner. For oneshot orders, all fee goes to protocol (no LP fee).
    /// @param feeBps The new fee in basis points (must be between MIN_FEE and MAX_FEE)
    function setOneshotProtocolFeeBps(uint32 feeBps) external onlyOwner {
        uint32 oldFeeBps = _gridState.oneshotProtocolFeeBps;
        _gridState.setOneshotProtocolFeeBps(feeBps);
        emit IOrderEvents.OneshotProtocolFeeChanged(msg.sender, oldFeeBps, feeBps);
    }

    /// @notice Get the current protocol fee for oneshot orders
    /// @return The oneshot protocol fee in basis points
    function getOneshotProtocolFeeBps() external view returns (uint32) {
        return _gridState.getOneshotProtocolFeeBps();
    }

    /// @notice Pauses all trading operations
    /// @dev Only callable by the owner. Affects order placement and filling.
    ///      Cancellation and withdrawal operations remain available when paused.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses all trading operations
    /// @dev Only callable by the owner
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IGridEx
    function setStrategyWhitelist(address strategy, bool whitelisted) external override onlyOwner {
        require(strategy != address(0), "Invalid strategy address");
        whitelistedStrategies[strategy] = whitelisted;
        emit IOrderEvents.StrategyWhitelistUpdated(msg.sender, strategy, whitelisted);
    }

    /// @inheritdoc IGridEx
    function isStrategyWhitelisted(address strategy) external view override returns (bool) {
        return whitelistedStrategies[strategy];
    }
}
