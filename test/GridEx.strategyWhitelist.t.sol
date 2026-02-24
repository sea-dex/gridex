// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";

import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {IOrderErrors} from "../src/interfaces/IOrderErrors.sol";
import {IOrderEvents} from "../src/interfaces/IOrderEvents.sol";
import {IProtocolErrors} from "../src/interfaces/IProtocolErrors.sol";
import {GridExRouter} from "../src/GridExRouter.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {CancelFacet} from "../src/facets/CancelFacet.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {ViewFacet} from "../src/facets/ViewFacet.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {ProtocolConstants} from "../src/libraries/ProtocolConstants.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

contract GridExStrategyWhitelistTest is Test {
    WETH public weth;
    GridExRouter public router;
    TradeFacet public tradeFacet;
    CancelFacet public cancelFacet;
    AdminFacet public adminFacet;
    ViewFacet public viewFacet;
    Linear public linear;
    Linear public linear2;
    SEA public sea;
    USDC public usdc;
    address public vault = address(0x0888880);

    /// @dev `exchange` is the router address cast to payable for compatibility
    address payable public exchange;

    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;
    address maker = address(0x100);
    address nonOwner = address(0x200);

    function setUp() public {
        weth = new WETH();
        sea = new SEA();
        usdc = new USDC();

        // Deploy facets
        tradeFacet = new TradeFacet();
        cancelFacet = new CancelFacet();
        adminFacet = new AdminFacet();
        viewFacet = new ViewFacet();

        // Deploy Router (with admin facet address for bootstrapping)
        router = new GridExRouter(address(this), vault, address(adminFacet));
        exchange = payable(address(router));

        // Register all selectors
        _registerAllSelectors();

        // Configure chain-specific settings
        AdminFacet(exchange).setWETH(address(weth));
        AdminFacet(exchange).setQuoteToken(Currency.wrap(address(usdc)), ProtocolConstants.QUOTE_PRIORITY_USD);
        AdminFacet(exchange).setQuoteToken(Currency.wrap(address(weth)), ProtocolConstants.QUOTE_PRIORITY_WETH);

        // Deploy and whitelist strategy
        linear = new Linear(exchange);
        linear2 = new Linear(exchange);

        // Set oneshot protocol fee
        AdminFacet(exchange).setOneshotProtocolFeeBps(500);

        // Give maker some tokens
        // forge-lint: disable-next-line
        sea.transfer(maker, 1000000 ether);
        // forge-lint: disable-next-line
        usdc.transfer(maker, 10000_000_000);

        vm.startPrank(maker);
        sea.approve(exchange, type(uint128).max);
        usdc.approve(exchange, type(uint128).max);
        vm.stopPrank();
    }

    function _registerAllSelectors() internal {
        // TradeFacet selectors
        bytes4[] memory selectors = new bytes4[](6);
        address[] memory facets = new address[](6);

        selectors[0] = TradeFacet.placeGridOrders.selector;
        facets[0] = address(tradeFacet);
        selectors[1] = TradeFacet.placeETHGridOrders.selector;
        facets[1] = address(tradeFacet);
        selectors[2] = TradeFacet.fillAskOrder.selector;
        facets[2] = address(tradeFacet);
        selectors[3] = TradeFacet.fillAskOrders.selector;
        facets[3] = address(tradeFacet);
        selectors[4] = TradeFacet.fillBidOrder.selector;
        facets[4] = address(tradeFacet);
        selectors[5] = TradeFacet.fillBidOrders.selector;
        facets[5] = address(tradeFacet);

        AdminFacet(exchange).batchSetFacet(selectors, facets);

        // CancelFacet selectors
        bytes4[] memory cancelSel = new bytes4[](5);
        address[] memory cancelFac = new address[](5);

        cancelSel[0] = CancelFacet.cancelGrid.selector;
        cancelFac[0] = address(cancelFacet);
        cancelSel[1] = bytes4(keccak256("cancelGridOrders(address,uint256,uint32,uint32)"));
        cancelFac[1] = address(cancelFacet);
        cancelSel[2] = bytes4(keccak256("cancelGridOrders(uint128,address,uint256[],uint32)"));
        cancelFac[2] = address(cancelFacet);
        cancelSel[3] = CancelFacet.withdrawGridProfits.selector;
        cancelFac[3] = address(cancelFacet);
        cancelSel[4] = CancelFacet.modifyGridFee.selector;
        cancelFac[4] = address(cancelFacet);

        AdminFacet(exchange).batchSetFacet(cancelSel, cancelFac);

        // AdminFacet selectors (beyond bootstrap)
        bytes4[] memory adminSel = new bytes4[](9);
        address[] memory adminFac = new address[](9);

        adminSel[0] = AdminFacet.setWETH.selector;
        adminFac[0] = address(adminFacet);
        adminSel[1] = AdminFacet.setQuoteToken.selector;
        adminFac[1] = address(adminFacet);
        adminSel[2] = AdminFacet.setStrategyWhitelist.selector;
        adminFac[2] = address(adminFacet);
        adminSel[3] = AdminFacet.setOneshotProtocolFeeBps.selector;
        adminFac[3] = address(adminFacet);
        adminSel[4] = AdminFacet.pause.selector;
        adminFac[4] = address(adminFacet);
        adminSel[5] = AdminFacet.unpause.selector;
        adminFac[5] = address(adminFacet);
        adminSel[6] = AdminFacet.rescueEth.selector;
        adminFac[6] = address(adminFacet);
        adminSel[7] = AdminFacet.transferOwnership.selector;
        adminFac[7] = address(adminFacet);
        adminSel[8] = AdminFacet.setFacet.selector;
        adminFac[8] = address(adminFacet);

        AdminFacet(exchange).batchSetFacet(adminSel, adminFac);

        // ViewFacet selectors
        bytes4[] memory viewSel = new bytes4[](12);
        address[] memory viewFac = new address[](12);

        viewSel[0] = ViewFacet.getGridOrder.selector;
        viewFac[0] = address(viewFacet);
        viewSel[1] = ViewFacet.getGridOrders.selector;
        viewFac[1] = address(viewFacet);
        viewSel[2] = ViewFacet.getGridProfits.selector;
        viewFac[2] = address(viewFacet);
        viewSel[3] = ViewFacet.getGridConfig.selector;
        viewFac[3] = address(viewFacet);
        viewSel[4] = ViewFacet.getOneshotProtocolFeeBps.selector;
        viewFac[4] = address(viewFacet);
        viewSel[5] = ViewFacet.isStrategyWhitelisted.selector;
        viewFac[5] = address(viewFacet);
        viewSel[6] = ViewFacet.getPairTokens.selector;
        viewFac[6] = address(viewFacet);
        viewSel[7] = ViewFacet.getPairIdByTokens.selector;
        viewFac[7] = address(viewFacet);
        viewSel[8] = ViewFacet.paused.selector;
        viewFac[8] = address(viewFacet);
        viewSel[9] = ViewFacet.owner.selector;
        viewFac[9] = address(viewFacet);
        viewSel[10] = ViewFacet.vault.selector;
        viewFac[10] = address(viewFacet);
        viewSel[11] = ViewFacet.WETH.selector;
        viewFac[11] = address(viewFacet);

        AdminFacet(exchange).batchSetFacet(viewSel, viewFac);
    }

    function test_setStrategyWhitelist_onlyOwner() public {
        // Non-owner should not be able to whitelist
        vm.startPrank(nonOwner);
        vm.expectRevert(AdminFacet.NotOwner.selector);
        AdminFacet(exchange).setStrategyWhitelist(address(linear), true);
        vm.stopPrank();

        // Owner should be able to whitelist
        AdminFacet(exchange).setStrategyWhitelist(address(linear), true);
        assertTrue(ViewFacet(exchange).isStrategyWhitelisted(address(linear)));
    }

    function test_setStrategyWhitelist_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IOrderEvents.StrategyWhitelistUpdated(address(this), address(linear), true);
        AdminFacet(exchange).setStrategyWhitelist(address(linear), true);
    }

    function test_setStrategyWhitelist_canRemove() public {
        // Whitelist first
        AdminFacet(exchange).setStrategyWhitelist(address(linear), true);
        assertTrue(ViewFacet(exchange).isStrategyWhitelisted(address(linear)));

        // Remove from whitelist
        AdminFacet(exchange).setStrategyWhitelist(address(linear), false);
        assertFalse(ViewFacet(exchange).isStrategyWhitelisted(address(linear)));
    }

    function test_setStrategyWhitelist_revertZeroAddress() public {
        vm.expectRevert(IProtocolErrors.InvalidAddress.selector);
        AdminFacet(exchange).setStrategyWhitelist(address(0), true);
    }

    function test_placeGridOrders_revertNonWhitelistedAskStrategy() public {
        // Don't whitelist the strategy
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 askPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: 5,
            bidOrderCount: 0,
            baseAmount: perBaseAmt,
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(0, -int256(gap)),
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.StrategyNotWhitelisted.selector);
        TradeFacet(exchange).placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    function test_placeGridOrders_revertNonWhitelistedBidStrategy() public {
        // Whitelist only linear, not linear2
        AdminFacet(exchange).setStrategyWhitelist(address(linear), true);

        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 bidPrice0 = uint256((48 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: 0,
            bidOrderCount: 5,
            baseAmount: perBaseAmt,
            askStrategy: linear,
            bidStrategy: linear2, // Not whitelisted
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.StrategyNotWhitelisted.selector);
        TradeFacet(exchange).placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();
    }

    function test_placeGridOrders_successWithWhitelistedStrategy() public {
        // Whitelist the strategy
        AdminFacet(exchange).setStrategyWhitelist(address(linear), true);

        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 askPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 bidPrice0 = uint256((48 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: perBaseAmt,
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        TradeFacet(exchange).placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        // Verify grid was created
        IGridOrder.GridConfig memory config = ViewFacet(exchange).getGridConfig(1);
        assertEq(config.owner, maker);
        assertEq(config.askOrderCount, 5);
        assertEq(config.bidOrderCount, 5);
    }

    function test_placeETHGridOrders_revertNonWhitelistedStrategy() public {
        // Don't whitelist the strategy
        uint128 perBaseAmt = 1 ether;
        uint256 askPrice0 = uint256((2000 * PRICE_MULTIPLIER) / (10 ** 12));
        uint256 gap = uint256((10 * PRICE_MULTIPLIER) / (10 ** 12));

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: 5,
            bidOrderCount: 0,
            baseAmount: perBaseAmt,
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(0, -int256(gap)),
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.deal(maker, 10 ether);
        vm.startPrank(maker);
        vm.expectRevert(IOrderErrors.StrategyNotWhitelisted.selector);
        TradeFacet(exchange).placeETHGridOrders{value: 5 ether}(
            Currency.wrap(address(0)), Currency.wrap(address(usdc)), param
        );
        vm.stopPrank();
    }

    function test_multipleStrategiesCanBeWhitelisted() public {
        // Whitelist both strategies
        AdminFacet(exchange).setStrategyWhitelist(address(linear), true);
        AdminFacet(exchange).setStrategyWhitelist(address(linear2), true);

        assertTrue(ViewFacet(exchange).isStrategyWhitelisted(address(linear)));
        assertTrue(ViewFacet(exchange).isStrategyWhitelisted(address(linear2)));

        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 askPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 bidPrice0 = uint256((48 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        // Use different strategies for ask and bid
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: 5,
            bidOrderCount: 5,
            baseAmount: perBaseAmt,
            askStrategy: linear,
            bidStrategy: linear2,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        TradeFacet(exchange).placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        // Verify grid was created with different strategies
        IGridOrder.GridConfig memory config = ViewFacet(exchange).getGridConfig(1);
        assertEq(address(config.askStrategy), address(linear));
        assertEq(address(config.bidStrategy), address(linear2));
    }
}
