// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";

import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {GridExRouter} from "../src/GridExRouter.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {CancelFacet} from "../src/facets/CancelFacet.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {ViewFacet} from "../src/facets/ViewFacet.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {ProtocolConstants} from "../src/libraries/ProtocolConstants.sol";
import {Lens} from "../src/libraries/Lens.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

contract GridExPlaceTest is Test {
    WETH public weth;
    GridExRouter public router;
    TradeFacet public tradeFacet;
    CancelFacet public cancelFacet;
    AdminFacet public adminFacet;
    ViewFacet public viewFacet;
    Linear public linear;
    SEA public sea;
    USDC public usdc;

    /// @dev `exchange` is the router address cast to payable for compatibility
    address payable public exchange;

    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;

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
        router = new GridExRouter(address(this), address(0x0888880), address(adminFacet));
        exchange = payable(address(router));

        // Register all selectors
        _registerAllSelectors();

        // Configure chain-specific settings
        AdminFacet(exchange).setWETH(address(weth));
        AdminFacet(exchange).setQuoteToken(Currency.wrap(address(usdc)), ProtocolConstants.QUOTE_PRIORITY_USD);
        AdminFacet(exchange).setQuoteToken(Currency.wrap(address(weth)), ProtocolConstants.QUOTE_PRIORITY_WETH);

        // Deploy and whitelist strategy
        linear = new Linear(exchange);
        AdminFacet(exchange).setStrategyWhitelist(address(linear), true);
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
        bytes4[] memory adminSel = new bytes4[](10);
        address[] memory adminFac = new address[](10);

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
        adminSel[8] = AdminFacet.setFacetAllowlist.selector;
        adminFac[8] = address(adminFacet);
        adminSel[9] = AdminFacet.setFacet.selector;
        adminFac[9] = address(adminFacet);

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

    function test_PlaceAskGridOrder() public {
        uint16 asks = 13;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 baseAmt = uint256(asks) * perBaseAmt;
        uint256 askPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        address maker = address(0x123);

        // forge-lint: disable-next-line
        sea.transfer(maker, baseAmt);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: asks,
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
        sea.approve(exchange, type(uint128).max);
        TradeFacet(exchange).placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        assertEq(sea.balanceOf(maker), 0);
        assertEq(uint256(asks) * perBaseAmt, sea.balanceOf(exchange));
    }

    function test_PlaceETHBaseAskGridOrder() public {
        uint16 asks = 13;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 baseAmt = uint256(asks) * perBaseAmt;
        uint256 askPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        address maker = address(0x123);

        vm.deal(maker, baseAmt);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: asks,
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
        TradeFacet(exchange).placeETHGridOrders{value: baseAmt}(
            Currency.wrap(address(0)), Currency.wrap(address(usdc)), param
        );
        vm.stopPrank();

        assertEq(uint256(asks) * perBaseAmt, weth.balanceOf(exchange));
        assertEq(0, Currency.wrap(address(0)).balanceOf(exchange));
        assertEq(Currency.wrap(address(0)).balanceOf(maker), 0);
    }

    function test_PlaceBidGridOrder() public {
        uint16 bids = 10;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint256 bidPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        address maker = address(0x123);

        // forge-lint: disable-next-line
        usdc.transfer(maker, usdcAmt);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: 0,
            bidOrderCount: bids,
            baseAmount: perBaseAmt,
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        usdc.approve(exchange, type(uint128).max);
        TradeFacet(exchange).placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        assertEq(usdc.balanceOf(maker) > 0, true);
        assertEq(usdcAmt > usdc.balanceOf(exchange), true);
        assertEq(usdcAmt, usdc.balanceOf(maker) + usdc.balanceOf(exchange));
    }

    function test_PlaceETHQuoteBidGridOrder() public {
        uint16 bids = 10;
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 bidPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));
        address maker = address(0x123);

        (, uint128 ethAmt) = Lens.calcGridAmount(perBaseAmt, bidPrice0, gap, 0, bids);
        vm.deal(maker, ethAmt);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: 0,
            bidOrderCount: bids,
            baseAmount: perBaseAmt,
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
            fee: 500,
            compound: false,
            oneshot: false
        });

        vm.startPrank(maker);
        TradeFacet(exchange).placeETHGridOrders{value: ethAmt}(
            Currency.wrap(address(sea)), Currency.wrap(address(0)), param
        );
        vm.stopPrank();

        assertEq(Currency.wrap(address(0)).balanceOf(maker), 0);
        assertEq(Currency.wrap(address(0)).balanceOf(exchange), 0);
        assertEq(weth.balanceOf(maker), 0);
        assertEq(weth.balanceOf(exchange), ethAmt);
        assertEq(ethAmt, weth.balanceOf(exchange) + weth.balanceOf(maker));
    }

    function test_PlaceGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address maker = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint256 askPrice0 = uint256((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 bidPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        // forge-lint: disable-next-line
        usdc.transfer(maker, usdcAmt);
        // forge-lint: disable-next-line
        sea.transfer(maker, uint256(asks) * perBaseAmt);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: asks,
            bidOrderCount: bids,
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
        sea.approve(exchange, type(uint128).max);
        usdc.approve(exchange, type(uint128).max);
        TradeFacet(exchange).placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        assertEq(0, sea.balanceOf(maker));
        assertEq(usdc.balanceOf(maker) > 0, true);
        assertEq(uint256(asks) * perBaseAmt, sea.balanceOf(exchange));
        assertEq(usdcAmt > usdc.balanceOf(exchange), true);
        assertEq(usdcAmt, usdc.balanceOf(exchange) + usdc.balanceOf(maker));
    }

    function test_PlaceETHGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address maker = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint256 askPrice0 = uint256((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 bidPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        // eth/usdc
        // forge-lint: disable-next-line
        usdc.transfer(maker, usdcAmt);
        vm.deal(maker, uint256(asks) * perBaseAmt);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: asks,
            bidOrderCount: bids,
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
        usdc.approve(exchange, type(uint128).max);
        TradeFacet(exchange).placeETHGridOrders{value: uint256(asks) * perBaseAmt}(
            Currency.wrap(address(0)), Currency.wrap(address(usdc)), param
        );
        vm.stopPrank();

        assertEq(0, Currency.wrap(address(0)).balanceOf(maker));
        assertEq(usdc.balanceOf(maker) > 0, true);
        assertEq(0, Currency.wrap(address(0)).balanceOf(exchange));
        assertEq(uint256(asks) * perBaseAmt, weth.balanceOf(exchange));
        assertEq(usdcAmt > usdc.balanceOf(exchange), true);
        assertEq(usdcAmt, usdc.balanceOf(exchange) + usdc.balanceOf(maker));
    }

    // weth/usdc
    function test_PlaceWETHGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address maker = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 usdcAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint256 askPrice0 = uint256((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 bidPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        // eth/usdc
        // forge-lint: disable-next-line
        usdc.transfer(maker, usdcAmt);
        vm.deal(maker, uint256(asks) * perBaseAmt);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: asks,
            bidOrderCount: bids,
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
        weth.deposit{value: uint256(asks) * perBaseAmt}();
        usdc.approve(exchange, type(uint128).max);
        weth.approve(exchange, type(uint128).max);
        TradeFacet(exchange).placeGridOrders(Currency.wrap(address(weth)), Currency.wrap(address(usdc)), param);
        vm.stopPrank();

        assertEq(0, Currency.wrap(address(weth)).balanceOf(maker));
        assertEq(usdc.balanceOf(maker) > 0, true);
        assertEq(uint256(asks) * perBaseAmt, Currency.wrap(address(weth)).balanceOf(exchange));
        assertEq(usdcAmt > usdc.balanceOf(exchange), true);
        assertEq(usdcAmt, usdc.balanceOf(exchange) + usdc.balanceOf(maker));
    }

    // sea/weth
    function test_PlaceWETHQuoteGridOrder() public {
        // sell order: 5 - 6
        // buy order: 4 - 4.9
        uint16 asks = 10;
        uint16 bids = 20;
        address maker = address(0x123);
        uint128 perBaseAmt = 100 * 10 ** 18;
        uint256 baseAmt = perBaseAmt * asks;
        uint256 ethAmt = uint256(bids) * 5 * 100 * 10 ** 6;
        uint256 askPrice0 = uint256((50 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 bidPrice0 = uint256((49 * PRICE_MULTIPLIER) / 10 / (10 ** 12));
        uint256 gap = uint256((5 * PRICE_MULTIPLIER) / 10000 / (10 ** 12));

        // sea/weth
        // forge-lint: disable-next-line
        sea.transfer(maker, baseAmt);
        vm.deal(maker, ethAmt);

        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askOrderCount: asks,
            bidOrderCount: bids,
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
        weth.deposit{value: ethAmt}();
        sea.approve(exchange, type(uint128).max);
        weth.approve(exchange, type(uint128).max);
        TradeFacet(exchange).placeGridOrders(Currency.wrap(address(sea)), Currency.wrap(address(weth)), param);
        vm.stopPrank();

        assertEq(0, Currency.wrap(address(sea)).balanceOf(maker));
        assertEq(weth.balanceOf(maker) > 0, true);
        assertEq(baseAmt, Currency.wrap(address(sea)).balanceOf(exchange));
        assertEq(ethAmt > weth.balanceOf(exchange), true);
        assertEq(ethAmt, weth.balanceOf(maker) + weth.balanceOf(exchange));
    }
}
