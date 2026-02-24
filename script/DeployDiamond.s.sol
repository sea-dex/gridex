// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";

import {GridExRouter} from "../src/GridExRouter.sol";
import {Vault} from "../src/Vault.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {Geometry} from "../src/strategy/Geometry.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {ProtocolConstants} from "../src/libraries/ProtocolConstants.sol";

import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {CancelFacet} from "../src/facets/CancelFacet.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {ViewFacet} from "../src/facets/ViewFacet.sol";

/// @title DeployDiamond
/// @notice Deployment script for the GridEx Diamond (Router + Facets) architecture
contract DeployDiamond is Script {
    address public vault;
    address public router;
    address public tradeFacet;
    address public cancelFacet;
    address public adminFacet;
    address public viewFacet;
    address public linear;
    address public geometry;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address weth = vm.envAddress("WETH_ADDRESS");
        address usd = vm.envAddress("USD_ADDRESS");

        console.log("========================================");
        console.log("GridEx Diamond Deployment");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("WETH:", weth);
        console.log("USD:", usd);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Vault
        Vault v = new Vault(deployer);
        vault = address(v);
        console.log("[OK] Vault:", vault);

        // 2. Deploy facets
        TradeFacet tf = new TradeFacet();
        tradeFacet = address(tf);
        console.log("[OK] TradeFacet:", tradeFacet);

        CancelFacet cf = new CancelFacet();
        cancelFacet = address(cf);
        console.log("[OK] CancelFacet:", cancelFacet);

        AdminFacet af = new AdminFacet();
        adminFacet = address(af);
        console.log("[OK] AdminFacet:", adminFacet);

        ViewFacet vf = new ViewFacet();
        viewFacet = address(vf);
        console.log("[OK] ViewFacet:", viewFacet);

        // 3. Deploy Router (with admin facet for bootstrapping)
        GridExRouter r = new GridExRouter(deployer, vault, adminFacet);
        router = address(r);
        console.log("[OK] GridExRouter:", router);

        // 4. Register non-admin selectors via AdminFacet (admin selectors already bootstrapped)
        _registerSelectors(r);

        // 5. Configure chain-specific settings via AdminFacet
        AdminFacet(router).setWETH(weth);
        AdminFacet(router).setQuoteToken(Currency.wrap(usd), ProtocolConstants.QUOTE_PRIORITY_USD);
        AdminFacet(router).setQuoteToken(Currency.wrap(weth), ProtocolConstants.QUOTE_PRIORITY_WETH);
        console.log("[OK] WETH and quote tokens configured");

        // 6. Deploy Linear strategy pointing to router
        Linear l = new Linear(router);
        linear = address(l);
        console.log("[OK] Linear:", linear);

        // 7. Deploy Geometry strategy pointing to router
        Geometry g = new Geometry(router);
        geometry = address(g);
        console.log("[OK] Geometry:", geometry);

        // 8. Whitelist strategies
        AdminFacet(router).setStrategyWhitelist(linear, true);
        console.log("[OK] Linear strategy whitelisted");
        AdminFacet(router).setStrategyWhitelist(geometry, true);
        console.log("[OK] Geometry strategy whitelisted");

        // 9. Set oneshot protocol fee
        AdminFacet(router).setOneshotProtocolFeeBps(500);
        console.log("[OK] Oneshot protocol fee set to 500 bps");

        vm.stopBroadcast();

        _printSummary();
    }

    function _registerSelectors(GridExRouter) internal {
        // TradeFacet + CancelFacet + ViewFacet selectors
        // (AdminFacet selectors are bootstrapped in the Router constructor)

        // TradeFacet (6)
        bytes4[] memory tradeSel = new bytes4[](6);
        address[] memory tradeFac = new address[](6);

        tradeSel[0] = TradeFacet.placeGridOrders.selector;
        tradeFac[0] = tradeFacet;
        tradeSel[1] = TradeFacet.placeETHGridOrders.selector;
        tradeFac[1] = tradeFacet;
        tradeSel[2] = TradeFacet.fillAskOrder.selector;
        tradeFac[2] = tradeFacet;
        tradeSel[3] = TradeFacet.fillAskOrders.selector;
        tradeFac[3] = tradeFacet;
        tradeSel[4] = TradeFacet.fillBidOrder.selector;
        tradeFac[4] = tradeFacet;
        tradeSel[5] = TradeFacet.fillBidOrders.selector;
        tradeFac[5] = tradeFacet;

        AdminFacet(router).batchSetFacet(tradeSel, tradeFac);
        console.log("[OK] TradeFacet selectors registered");

        // CancelFacet (5)
        bytes4[] memory cancelSel = new bytes4[](5);
        address[] memory cancelFac = new address[](5);

        cancelSel[0] = CancelFacet.cancelGrid.selector;
        cancelFac[0] = cancelFacet;
        cancelSel[1] = bytes4(keccak256("cancelGridOrders(address,uint256,uint32,uint32)"));
        cancelFac[1] = cancelFacet;
        cancelSel[2] = bytes4(keccak256("cancelGridOrders(uint128,address,uint256[],uint32)"));
        cancelFac[2] = cancelFacet;
        cancelSel[3] = CancelFacet.withdrawGridProfits.selector;
        cancelFac[3] = cancelFacet;
        cancelSel[4] = CancelFacet.modifyGridFee.selector;
        cancelFac[4] = cancelFacet;

        AdminFacet(router).batchSetFacet(cancelSel, cancelFac);
        console.log("[OK] CancelFacet selectors registered");

        // Register ViewFacet selectors separately (they go through fallback)
        bytes4[] memory viewSelectors = new bytes4[](10);
        address[] memory viewFacets = new address[](10);
        uint256 vi = 0;

        viewSelectors[vi] = ViewFacet.getGridOrder.selector;
        viewFacets[vi++] = viewFacet;
        viewSelectors[vi] = ViewFacet.getGridOrders.selector;
        viewFacets[vi++] = viewFacet;
        viewSelectors[vi] = ViewFacet.getGridProfits.selector;
        viewFacets[vi++] = viewFacet;
        viewSelectors[vi] = ViewFacet.getGridConfig.selector;
        viewFacets[vi++] = viewFacet;
        viewSelectors[vi] = ViewFacet.getOneshotProtocolFeeBps.selector;
        viewFacets[vi++] = viewFacet;
        viewSelectors[vi] = ViewFacet.isStrategyWhitelisted.selector;
        viewFacets[vi++] = viewFacet;
        viewSelectors[vi] = ViewFacet.getPairTokens.selector;
        viewFacets[vi++] = viewFacet;
        viewSelectors[vi] = ViewFacet.getPairIdByTokens.selector;
        viewFacets[vi++] = viewFacet;
        viewSelectors[vi] = ViewFacet.paused.selector;
        viewFacets[vi++] = viewFacet;
        viewSelectors[vi] = ViewFacet.owner.selector;
        viewFacets[vi++] = viewFacet;

        AdminFacet(router).batchSetFacet(viewSelectors, viewFacets);
        console.log("[OK] View selectors registered");
    }

    function _printSummary() internal view {
        console.log("");
        console.log("========================================");
        console.log("Diamond Deployment Complete!");
        console.log("========================================");
        console.log("  Vault:", vault);
        console.log("  Router:", router);
        console.log("  TradeFacet:", tradeFacet);
        console.log("  CancelFacet:", cancelFacet);
        console.log("  AdminFacet:", adminFacet);
        console.log("  ViewFacet:", viewFacet);
        console.log("  Linear:", linear);
        console.log("  Geometry:", geometry);
    }
}
