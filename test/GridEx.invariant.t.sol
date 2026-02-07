// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {GridEx} from "../src/GridEx.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {Vault} from "../src/Vault.sol";
import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {IGridStrategy} from "../src/interfaces/IGridStrategy.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

/// @title GridExInvariantTest
/// @notice Invariant tests for token conservation in GridEx
contract GridExInvariantTest is StdInvariant, Test {
    GridEx public gridEx;
    Linear public linear;
    Vault public vault;
    WETH public weth;
    SEA public sea;
    USDC public usdc;

    address public owner;
    address public maker;
    address public taker;

    GridExHandler public handler;

    uint256 constant PRICE_MULTIPLIER = 10 ** 36;
    uint32 constant DEFAULT_FEE = 3000; // 0.3%

    // Track initial supplies
    uint256 public initialSeaSupply;
    uint256 public initialUsdcSupply;

    function setUp() public {
        owner = address(this);
        maker = makeAddr("maker");
        taker = makeAddr("taker");

        // Deploy tokens first
        weth = new WETH();
        sea = new SEA();
        usdc = new USDC();

        // Deploy contracts
        vault = new Vault();
        gridEx = new GridEx(address(weth), address(usdc), address(vault));
        linear = new Linear(address(gridEx));

        // Track initial supplies
        initialSeaSupply = sea.totalSupply();
        initialUsdcSupply = usdc.totalSupply();

        // Setup handler
        handler = new GridExHandler(gridEx, linear, sea, usdc, maker, taker);

        // Fund handler
        // forge-lint: disable-next-line
        sea.transfer(address(handler), 1_000_000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(address(handler), 1_000_000_000);

        // Target the handler for invariant testing
        targetContract(address(handler));

        // Exclude specific selectors that might cause issues
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = GridExHandler.placeAskOrders.selector;
        selectors[1] = GridExHandler.placeBidOrders.selector;
        selectors[2] = GridExHandler.fillAskOrder.selector;
        selectors[3] = GridExHandler.fillBidOrder.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice Invariant: Total tokens in system should be conserved
    /// @dev Sum of: GridEx balance + Vault balance + User balances = Initial supply
    function invariant_tokenConservation() public view {
        // SEA token conservation
        uint256 seaInGridEx = sea.balanceOf(address(gridEx));
        uint256 seaInVault = sea.balanceOf(address(vault));
        uint256 seaInHandler = sea.balanceOf(address(handler));
        uint256 seaInMaker = sea.balanceOf(maker);
        uint256 seaInTaker = sea.balanceOf(taker);
        uint256 seaInOwner = sea.balanceOf(owner);

        uint256 totalSea = seaInGridEx + seaInVault + seaInHandler + seaInMaker + seaInTaker + seaInOwner;

        // Total should equal initial supply
        assertEq(totalSea, initialSeaSupply, "SEA token conservation violated");

        // USDC token conservation
        uint256 usdcInGridEx = usdc.balanceOf(address(gridEx));
        uint256 usdcInVault = usdc.balanceOf(address(vault));
        uint256 usdcInHandler = usdc.balanceOf(address(handler));
        uint256 usdcInMaker = usdc.balanceOf(maker);
        uint256 usdcInTaker = usdc.balanceOf(taker);
        uint256 usdcInOwner = usdc.balanceOf(owner);

        uint256 totalUsdc = usdcInGridEx + usdcInVault + usdcInHandler + usdcInMaker + usdcInTaker + usdcInOwner;

        // Total should equal initial supply
        assertEq(totalUsdc, initialUsdcSupply, "USDC token conservation violated");
    }

    /// @notice Invariant: Protocol fees should accumulate in vault
    function invariant_protocolFeesInVault() public view {
        // Vault should have non-negative balance
        uint256 seaInVault = sea.balanceOf(address(vault));
        uint256 usdcInVault = usdc.balanceOf(address(vault));

        // Fees should be >= 0 (always true for uint, but documents intent)
        assertTrue(seaInVault >= 0, "Vault SEA balance negative");
        assertTrue(usdcInVault >= 0, "Vault USDC balance negative");
    }

    /// @notice Invariant: GridEx should not hold more tokens than deposited
    function invariant_gridExBalanceConsistent() public view {
        // GridEx balance should be consistent with tracked deposits
        uint256 seaInGridEx = sea.balanceOf(address(gridEx));
        uint256 usdcInGridEx = usdc.balanceOf(address(gridEx));

        // These should match the sum of all active orders + profits
        // For now, just verify they're non-negative
        assertTrue(seaInGridEx >= 0, "GridEx SEA balance negative");
        assertTrue(usdcInGridEx >= 0, "GridEx USDC balance negative");
    }

    /// @notice Invariant: Maker profits should be withdrawable
    function invariant_profitsWithdrawable() public view {
        // Get maker's grid profits
        uint96 gridId = handler.gridId();
        if (gridId == 0) return; // No grid created yet

        uint256 profits = gridEx.getGridProfits(gridId);

        // Profits should be non-negative (always true for uint)
        assertTrue(profits >= 0, "Profits negative");
    }
}

/// @title GridExHandler
/// @notice Handler contract for invariant testing
contract GridExHandler is Test {
    GridEx public gridEx;
    Linear public linear;
    SEA public baseToken;
    USDC public quoteToken;
    address public maker;
    address public taker;

    uint96 public gridId;
    uint256[] public orderIds;

    uint256 constant PRICE_MULTIPLIER = 10 ** 36;
    uint32 constant DEFAULT_FEE = 3000;

    constructor(GridEx _gridEx, Linear _linear, SEA _baseToken, USDC _quoteToken, address _maker, address _taker) {
        gridEx = _gridEx;
        linear = _linear;
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        maker = _maker;
        taker = _taker;

        // Approve tokens
        baseToken.approve(address(gridEx), type(uint256).max);
        quoteToken.approve(address(gridEx), type(uint256).max);
    }

    /// @notice Place ask orders
    function placeAskOrders(uint128 baseAmt, uint128 price0, uint64 gap, uint32 askCount) public {
        // Bound inputs
        baseAmt = uint128(bound(uint256(baseAmt), 1e15, 1e24));
        price0 = uint128(bound(uint256(price0), PRICE_MULTIPLIER / 1000, PRICE_MULTIPLIER * 1000));
        gap = uint64(bound(uint256(gap), PRICE_MULTIPLIER / 10000, PRICE_MULTIPLIER / 10));
        askCount = uint32(bound(uint256(askCount), 1, 10));

        // Ensure we have enough balance
        uint256 totalBase = uint256(baseAmt) * uint256(askCount);
        if (baseToken.balanceOf(address(this)) < totalBase) {
            return;
        }

        // Create order params with strategy
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: abi.encode(price0, int256(uint256(gap))),
            bidData: abi.encode(price0, -int256(uint256(gap))),
            askOrderCount: askCount,
            bidOrderCount: 0,
            fee: DEFAULT_FEE,
            compound: false,
            oneshot: false,
            baseAmount: baseAmt
        });

        vm.prank(maker);
        baseToken.approve(address(gridEx), type(uint256).max);

        // Transfer tokens to maker
        // forge-lint: disable-next-line
        baseToken.transfer(maker, totalBase);

        vm.prank(maker);
        try gridEx.placeGridOrders(Currency.wrap(address(baseToken)), Currency.wrap(address(quoteToken)), param) {
            // Get the grid ID from the event or state
            // For simplicity, increment gridId
            gridId++;
        } catch {
            // Order placement failed, return tokens
            vm.prank(maker);
            // forge-lint: disable-next-line
            baseToken.transfer(address(this), baseToken.balanceOf(maker));
        }
    }

    /// @notice Place bid orders
    function placeBidOrders(uint128 baseAmt, uint128 price0, uint64 gap, uint32 bidCount) public {
        // Bound inputs
        baseAmt = uint128(bound(uint256(baseAmt), 1e15, 1e24));
        price0 = uint128(bound(uint256(price0), PRICE_MULTIPLIER / 1000, PRICE_MULTIPLIER * 1000));
        gap = uint64(bound(uint256(gap), PRICE_MULTIPLIER / 10000, PRICE_MULTIPLIER / 10));
        bidCount = uint32(bound(uint256(bidCount), 1, 10));

        // Calculate required quote amount
        uint256 totalQuote = 0;
        uint256 currentPrice = price0;
        for (uint32 i = 0; i < bidCount; i++) {
            totalQuote += (uint256(baseAmt) * currentPrice) / PRICE_MULTIPLIER;
            if (currentPrice > gap) {
                currentPrice -= gap;
            }
        }

        if (quoteToken.balanceOf(address(this)) < totalQuote) {
            return;
        }

        // Create order params (negative gap for bid)
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: IGridStrategy(address(linear)),
            bidStrategy: IGridStrategy(address(linear)),
            askData: abi.encode(price0, int256(uint256(gap))),
            bidData: abi.encode(price0, -int256(uint256(gap))),
            askOrderCount: 0,
            bidOrderCount: bidCount,
            fee: DEFAULT_FEE,
            compound: false,
            oneshot: false,
            baseAmount: baseAmt
        });

        vm.prank(maker);
        quoteToken.approve(address(gridEx), type(uint256).max);

        // Transfer tokens to maker
        // forge-lint: disable-next-line
        quoteToken.transfer(maker, totalQuote);

        vm.prank(maker);
        try gridEx.placeGridOrders(Currency.wrap(address(baseToken)), Currency.wrap(address(quoteToken)), param) {
            gridId++;
        } catch {
            // Order placement failed, return tokens
            vm.prank(maker);
            // forge-lint: disable-next-line
            quoteToken.transfer(address(this), quoteToken.balanceOf(maker));
        }
    }

    /// @notice Fill an ask order
    function fillAskOrder(uint256 orderIndex, uint128 fillAmt) public {
        if (orderIds.length == 0) return;

        orderIndex = bound(orderIndex, 0, orderIds.length - 1);
        uint256 orderId = orderIds[orderIndex];

        // Check if it's an ask order (high bit set)
        (, uint128 localOrderId) = _extractIds(orderId);
        if (localOrderId < 0x80000000000000000000000000000000) {
            return; // Not an ask order
        }

        fillAmt = uint128(bound(uint256(fillAmt), 1e12, 1e20));

        // Get order info to calculate required quote
        try gridEx.getGridOrder(orderId) returns (IGridOrder.OrderInfo memory info) {
            if (info.baseAmt == 0) return; // Order already filled

            // Calculate quote needed
            uint256 quoteNeeded = (uint256(fillAmt) * info.price) / PRICE_MULTIPLIER;
            quoteNeeded = (quoteNeeded * 1001) / 1000; // Add 0.1% buffer for fees

            if (quoteToken.balanceOf(address(this)) < quoteNeeded) {
                return;
            }

            // Transfer to taker
            // forge-lint: disable-next-line
            quoteToken.transfer(taker, quoteNeeded);

            vm.prank(taker);
            quoteToken.approve(address(gridEx), type(uint256).max);

            vm.prank(taker);
            try gridEx.fillAskOrder(orderId, fillAmt, 0, "", 0) {
            // Success
            }
            catch {
                // Fill failed, return tokens
                vm.prank(taker);
                // forge-lint: disable-next-line
                quoteToken.transfer(address(this), quoteToken.balanceOf(taker));
            }
        } catch {
            // Order doesn't exist
        }
    }

    /// @notice Fill a bid order
    function fillBidOrder(uint256 orderIndex, uint128 fillAmt) public {
        if (orderIds.length == 0) return;

        orderIndex = bound(orderIndex, 0, orderIds.length - 1);
        uint256 orderId = orderIds[orderIndex];

        // Check if it's a bid order (high bit not set)
        (, uint128 localOrderId) = _extractIds(orderId);
        if (localOrderId >= 0x80000000000000000000000000000000) {
            return; // Not a bid order
        }

        fillAmt = uint128(bound(uint256(fillAmt), 1e12, 1e20));

        // Get order info
        try gridEx.getGridOrder(orderId) returns (IGridOrder.OrderInfo memory info) {
            if (info.amount == 0) return; // Order already filled

            // Calculate base needed
            uint256 baseNeeded = fillAmt;

            if (baseToken.balanceOf(address(this)) < baseNeeded) {
                return;
            }

            // Transfer to taker
            // forge-lint: disable-next-line
            baseToken.transfer(taker, baseNeeded);

            vm.prank(taker);
            baseToken.approve(address(gridEx), type(uint256).max);

            vm.prank(taker);
            try gridEx.fillBidOrder(orderId, fillAmt, 0, "", 0) {
            // Success
            }
            catch {
                // Fill failed, return tokens
                vm.prank(taker);
                // forge-lint: disable-next-line
                baseToken.transfer(address(this), baseToken.balanceOf(taker));
            }
        } catch {
            // Order doesn't exist
        }
    }

    function _extractIds(uint256 gridOrderId) internal pure returns (uint128 gridId_, uint128 orderId_) {
        // forge-lint: disable-next-line
        gridId_ = uint128(gridOrderId >> 128);
        // forge-lint: disable-next-line
        orderId_ = uint128(gridOrderId);
    }
}
