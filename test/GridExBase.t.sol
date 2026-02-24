// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";

import {IGridOrder} from "../src/interfaces/IGridOrder.sol";
import {IGridEx} from "../src/interfaces/IGridEx.sol";
import {GridExRouter} from "../src/GridExRouter.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {CancelFacet} from "../src/facets/CancelFacet.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {ViewFacet} from "../src/facets/ViewFacet.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {ProtocolConstants} from "../src/libraries/ProtocolConstants.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {Lens} from "../src/libraries/Lens.sol";

import {SEA} from "./utils/SEA.sol";
import {USDC} from "./utils/USDC.sol";
import {WETH} from "./utils/WETH.sol";

/// @title GridExBaseTest
/// @notice Base test harness for GridExRouter (diamond architecture)
/// @dev Provides the same interface as before but backed by Router + Facets.
///      The `exchange` variable is the router address, typed as IGridEx for direct method calls.
contract GridExBaseTest is Test {
    WETH public weth;
    GridExRouter public router;
    TradeFacet public tradeFacet;
    CancelFacet public cancelFacet;
    AdminFacet public adminFacet;
    ViewFacet public viewFacet;
    Linear public linear;
    SEA public sea;
    USDC public usdc;
    address public vault = address(0x0888880);

    /// @dev `exchange` is the router address typed as IGridEx for direct method calls
    IGridEx public exchange;

    uint256 public constant PRICE_MULTIPLIER = 10 ** 36;
    address maker = address(0x100);
    address taker = address(0x200);
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256 initialETHAmt = 10 ether;
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256 initialSEAAmt = 1000000 ether;
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256 initialUSDCAmt = 10000_000_000;

    function setUp() public virtual {
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
        exchange = IGridEx(address(router));

        // Register all selectors (admin facet selectors already bootstrapped in constructor)
        _registerAllSelectors();

        // Configure chain-specific settings
        AdminFacet(address(exchange)).setWETH(address(weth));
        AdminFacet(address(exchange)).setQuoteToken(Currency.wrap(address(usdc)), ProtocolConstants.QUOTE_PRIORITY_USD);
        AdminFacet(address(exchange)).setQuoteToken(Currency.wrap(address(weth)), ProtocolConstants.QUOTE_PRIORITY_WETH);

        // Deploy and whitelist strategy
        linear = new Linear(address(exchange));
        AdminFacet(address(exchange)).setStrategyWhitelist(address(linear), true);

        // Set oneshot protocol fee (500 bps = 0.05%)
        AdminFacet(address(exchange)).setOneshotProtocolFeeBps(500);

        // Fund maker and taker
        vm.deal(maker, initialETHAmt);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        sea.transfer(maker, initialSEAAmt);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        usdc.transfer(maker, initialUSDCAmt);

        vm.deal(taker, initialETHAmt);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        sea.transfer(taker, initialSEAAmt);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        usdc.transfer(taker, initialUSDCAmt);

        vm.startPrank(maker);
        weth.approve(address(exchange), type(uint128).max);
        sea.approve(address(exchange), type(uint128).max);
        usdc.approve(address(exchange), type(uint128).max);
        vm.stopPrank();

        vm.startPrank(taker);
        weth.approve(address(exchange), type(uint128).max);
        sea.approve(address(exchange), type(uint128).max);
        usdc.approve(address(exchange), type(uint128).max);
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

        AdminFacet(address(exchange)).batchSetFacet(selectors, facets);

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

        AdminFacet(address(exchange)).batchSetFacet(cancelSel, cancelFac);

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

        AdminFacet(address(exchange)).batchSetFacet(adminSel, adminFac);

        // ViewFacet selectors
        bytes4[] memory viewSel = new bytes4[](13);
        address[] memory viewFac = new address[](13);

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
        viewSel[8] = ViewFacet.getPairById.selector;
        viewFac[8] = address(viewFacet);
        viewSel[9] = ViewFacet.paused.selector;
        viewFac[9] = address(viewFacet);
        viewSel[10] = ViewFacet.owner.selector;
        viewFac[10] = address(viewFacet);
        viewSel[11] = ViewFacet.vault.selector;
        viewFac[11] = address(viewFacet);
        viewSel[12] = ViewFacet.WETH.selector;
        viewFac[12] = address(viewFacet);

        AdminFacet(address(exchange)).batchSetFacet(viewSel, viewFac);
    }

    function toGridOrderId(uint128 gridId, uint128 orderId) internal pure returns (uint256) {
        return uint256(uint256(gridId) << 128) | uint256(orderId);
    }

    function _placeOrdersBy(
        address who,
        address base,
        address quote,
        uint128 perBaseAmt,
        uint16 asks,
        uint16 bids,
        uint256 askPrice0,
        uint256 bidPrice0,
        uint256 gap,
        bool compound,
        uint32 fee
    ) internal {
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: asks,
            bidOrderCount: bids,
            baseAmount: perBaseAmt,
            fee: fee,
            compound: compound,
            oneshot: false
        });

        vm.startPrank(who);
        if (base == address(0) || quote == address(0)) {
            uint256 val = (base == address(0)) ? perBaseAmt * asks : (perBaseAmt * bids * bidPrice0) / PRICE_MULTIPLIER;

            TradeFacet(address(exchange)).placeETHGridOrders{value: val}(
                Currency.wrap(base), Currency.wrap(quote), param
            );
        } else {
            TradeFacet(address(exchange)).placeGridOrders(Currency.wrap(base), Currency.wrap(quote), param);
        }
        vm.stopPrank();
    }

    function _placeOrders(
        address base,
        address quote,
        uint128 perBaseAmt,
        uint16 asks,
        uint16 bids,
        uint256 askPrice0,
        uint256 bidPrice0,
        uint256 gap,
        bool compound,
        uint32 fee
    ) internal {
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: asks,
            bidOrderCount: bids,
            baseAmount: perBaseAmt,
            fee: fee,
            compound: compound,
            oneshot: false
        });

        vm.startPrank(maker);
        if (base == address(0) || quote == address(0)) {
            uint256 val = (base == address(0)) ? perBaseAmt * asks : (perBaseAmt * bids * bidPrice0) / PRICE_MULTIPLIER;

            TradeFacet(address(exchange)).placeETHGridOrders{value: val}(
                Currency.wrap(base), Currency.wrap(quote), param
            );
        } else {
            TradeFacet(address(exchange)).placeGridOrders(Currency.wrap(base), Currency.wrap(quote), param);
        }
        vm.stopPrank();
    }

    function _placeOneshotOrders(
        address base,
        address quote,
        uint128 perBaseAmt,
        uint16 asks,
        uint16 bids,
        uint256 askPrice0,
        uint256 bidPrice0,
        uint256 gap,
        bool compound,
        uint32 fee
    ) internal {
        IGridOrder.GridOrderParam memory param = IGridOrder.GridOrderParam({
            askStrategy: linear,
            bidStrategy: linear,
            // forge-lint: disable-next-line(unsafe-typecast)
            askData: abi.encode(askPrice0, int256(gap)),
            // forge-lint: disable-next-line(unsafe-typecast)
            bidData: abi.encode(bidPrice0, -int256(gap)),
            askOrderCount: asks,
            bidOrderCount: bids,
            baseAmount: perBaseAmt,
            fee: fee,
            compound: compound,
            oneshot: true
        });

        vm.startPrank(maker);
        if (base == address(0) || quote == address(0)) {
            uint256 val = (base == address(0)) ? perBaseAmt * asks : (perBaseAmt * bids * bidPrice0) / PRICE_MULTIPLIER;

            TradeFacet(address(exchange)).placeETHGridOrders{value: val}(
                Currency.wrap(base), Currency.wrap(quote), param
            );
        } else {
            TradeFacet(address(exchange)).placeGridOrders(Currency.wrap(base), Currency.wrap(quote), param);
        }
        vm.stopPrank();
    }

    // just for ask order
    // return: fillVol, reverse order quote amount, grid profit, fee
    function calcQuoteVolReversed(
        uint256 price,
        uint256 gap,
        uint128 fillAmt,
        uint128 baseAmt,
        uint128 currOrderQuoteAmt,
        uint32 feebps
    ) internal pure returns (uint128, uint128, uint128, uint128) {
        (uint128 quoteVol, uint128 fee) = Lens.calcAskOrderQuoteAmount(price, fillAmt, feebps);
        uint128 lpfee = calcMakerFee(fee);
        uint128 quota = Lens.calcQuoteAmount(baseAmt, price - gap, false);
        if (currOrderQuoteAmt >= quota) {
            return (quoteVol, quota, quota + lpfee, fee);
        }
        if (currOrderQuoteAmt + quoteVol + lpfee > quota) {
            return (quoteVol, quota, currOrderQuoteAmt + quoteVol + lpfee - quota, fee);
        }
        return (quoteVol, quoteVol + lpfee, 0, fee);
    }

    // just for ask order
    // return: fillVol, reverse order quote amount, fee
    function calcQuoteVolReversedCompound(uint256 price, uint128 fillAmt, uint32 feebps)
        internal
        pure
        returns (uint128, uint128, uint128)
    {
        (uint128 quoteVol, uint128 fee) = Lens.calcAskOrderQuoteAmount(price, fillAmt, feebps);
        uint128 lpfee = calcMakerFee(fee);
        return (quoteVol, quoteVol + lpfee, fee);
    }

    function calcProtocolFee(uint128 fee) internal pure returns (uint128) {
        // here if change to fee >> 2, will cause stack too deep problem
        return fee / 4;
    }

    function calcMakerFee(uint128 fee) internal pure returns (uint128) {
        return fee - (fee / 4);
        // return fee - (fee >> 1);
    }
}
