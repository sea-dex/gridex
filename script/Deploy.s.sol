// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";

import {GridExRouter} from "../src/GridExRouter.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {CancelFacet} from "../src/facets/CancelFacet.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {ViewFacet} from "../src/facets/ViewFacet.sol";
import {Vault} from "../src/Vault.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {Geometry} from "../src/strategy/Geometry.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {ProtocolConstants} from "../src/libraries/ProtocolConstants.sol";
import {DeployConfig} from "./config/DeployConfig.sol";

/// @title Deploy
/// @notice Production deployment script for GridEx protocol with diamond architecture
/// @dev Uses CREATE2 via the deterministic deployment proxy for same addresses across chains
///
/// ## How to achieve same contract addresses across all chains:
///
/// The contract address from CREATE2 is determined by:
///   address = keccak256(0xff ++ deployer ++ salt ++ keccak256(bytecode))[12:]
///
/// For the SAME address across chains, you need:
/// 1. Same CREATE2 deployer address (using 0x4e59b44847b379578588920cA78FbF26c0B4956C)
/// 2. Same salt (using DEPLOYMENT_SALT)
/// 3. Same bytecode INCLUDING constructor arguments
///
/// GridExRouter uses diamond pattern:
/// - Router: Constructor args include (owner, vault, adminFacet)
/// - Facets: No constructor args, same address everywhere
/// - Chain-specific config (WETH, quote tokens) is set via
///   setWETH() and setQuoteToken() after deployment
///
/// ## Usage:
///
/// 1. Preview addresses:
///    forge script script/Deploy.s.sol --sig "preview()" --rpc-url $RPC_URL
///
/// 2. Deploy all contracts:
///    forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
///
/// 3. Deploy with custom WETH/USD:
///    WETH_ADDRESS=0x... USD_ADDRESS=0x... forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
///
contract Deploy is Script {
    // ============ Constants ============

    /// @notice The salt used for CREATE2 deployment
    /// @dev CRITICAL: This must be the same across all chains for deterministic addresses
    bytes32 public constant DEPLOYMENT_SALT = keccak256("GridEx.V1.2024.Production.Diamond");

    /// @notice Deterministic deployment proxy (same address on all EVM chains)
    /// @dev Deployed via keyless deployment, available on most chains
    /// @dev See: https://github.com/Arachnid/deterministic-deployment-proxy
    address public constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // ============ State ============
    address public vault;
    address public adminFacet;
    address public tradeFacet;
    address public cancelFacet;
    address public viewFacet;
    address public router;
    address public linear;
    address public geometry;

    // ============ Main Entry Points ============

    /// @notice Main deployment function - deploys all contracts
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get chain config or use environment variables
        (address weth, address usd) = _getTokenAddresses();

        console.log("========================================");
        console.log("GridEx Protocol Deployment (Diamond)");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("WETH:", weth);
        console.log("USD:", usd);
        console.log("");

        // Verify CREATE2 deployer exists
        require(CREATE2_DEPLOYER.code.length > 0, "CREATE2 deployer not available on this chain");

        // Preview expected addresses (same on all chains)
        (
            address expectedVault,
            address expectedAdminFacet,
            address expectedTradeFacet,
            address expectedCancelFacet,
            address expectedViewFacet,
            address expectedRouter,
            address expectedLinear,
            address expectedGeometry
        ) = computeAddressesWithOwner(deployer);

        console.log("Expected Addresses:");
        console.log("  Vault:", expectedVault);
        console.log("  AdminFacet:", expectedAdminFacet);
        console.log("  TradeFacet:", expectedTradeFacet);
        console.log("  CancelFacet:", expectedCancelFacet);
        console.log("  ViewFacet:", expectedViewFacet);
        console.log("  Router:", expectedRouter);
        console.log("  Linear:", expectedLinear);
        console.log("  Geometry:", expectedGeometry);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Vault (with deployer as owner)
        bytes32 vaultSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Vault"));
        bytes memory vaultBytecode = abi.encodePacked(type(Vault).creationCode, abi.encode(deployer));
        vault = _deployContract(vaultSalt, vaultBytecode, "Vault");
        require(vault == expectedVault, "Vault address mismatch!");

        // Deploy AdminFacet (no constructor args)
        bytes32 adminFacetSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "AdminFacet"));
        bytes memory adminFacetBytecode = type(AdminFacet).creationCode;
        adminFacet = _deployContract(adminFacetSalt, adminFacetBytecode, "AdminFacet");
        require(adminFacet == expectedAdminFacet, "AdminFacet address mismatch!");

        // Deploy TradeFacet (no constructor args)
        bytes32 tradeFacetSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "TradeFacet"));
        bytes memory tradeFacetBytecode = type(TradeFacet).creationCode;
        tradeFacet = _deployContract(tradeFacetSalt, tradeFacetBytecode, "TradeFacet");
        require(tradeFacet == expectedTradeFacet, "TradeFacet address mismatch!");

        // Deploy CancelFacet (no constructor args)
        bytes32 cancelFacetSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "CancelFacet"));
        bytes memory cancelFacetBytecode = type(CancelFacet).creationCode;
        cancelFacet = _deployContract(cancelFacetSalt, cancelFacetBytecode, "CancelFacet");
        require(cancelFacet == expectedCancelFacet, "CancelFacet address mismatch!");

        // Deploy ViewFacet (no constructor args)
        bytes32 viewFacetSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "ViewFacet"));
        bytes memory viewFacetBytecode = type(ViewFacet).creationCode;
        viewFacet = _deployContract(viewFacetSalt, viewFacetBytecode, "ViewFacet");
        require(viewFacet == expectedViewFacet, "ViewFacet address mismatch!");

        // Deploy Router (with admin facet for bootstrapping)
        bytes32 routerSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Router"));
        bytes memory routerBytecode =
            abi.encodePacked(type(GridExRouter).creationCode, abi.encode(deployer, vault, adminFacet));
        router = _deployContract(routerSalt, routerBytecode, "GridExRouter");
        require(router == expectedRouter, "Router address mismatch!");

        console.log("[OK] GridExRouter initialized");

        // Register all facet selectors
        _registerAllSelectors();

        // Configure chain-specific WETH and quote tokens
        AdminFacet(router).setWETH(weth);
        AdminFacet(router).setQuoteToken(Currency.wrap(usd), ProtocolConstants.QUOTE_PRIORITY_USD);
        AdminFacet(router).setQuoteToken(Currency.wrap(weth), ProtocolConstants.QUOTE_PRIORITY_WETH);
        console.log("[OK] WETH and quote tokens configured");

        // Deploy Linear
        bytes32 linearSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Linear"));
        bytes memory linearBytecode = abi.encodePacked(type(Linear).creationCode, abi.encode(router));
        linear = _deployContract(linearSalt, linearBytecode, "Linear");
        require(linear == expectedLinear, "Linear address mismatch!");

        // Deploy Geometry
        bytes32 geometrySalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Geometry"));
        bytes memory geometryBytecode = abi.encodePacked(type(Geometry).creationCode, abi.encode(router));
        geometry = _deployContract(geometrySalt, geometryBytecode, "Geometry");
        require(geometry == expectedGeometry, "Geometry address mismatch!");

        // Configure: Whitelist Linear strategy
        if (!ViewFacet(router).isStrategyWhitelisted(linear)) {
            AdminFacet(router).setStrategyWhitelist(linear, true);
            console.log("[OK] Linear strategy whitelisted");
        } else {
            console.log("[SKIP] Linear already whitelisted");
        }

        // Configure: Whitelist Geometry strategy
        if (!ViewFacet(router).isStrategyWhitelisted(geometry)) {
            AdminFacet(router).setStrategyWhitelist(geometry, true);
            console.log("[OK] Geometry strategy whitelisted");
        } else {
            console.log("[SKIP] Geometry already whitelisted");
        }

        vm.stopBroadcast();

        _printSummary(weth, usd);
    }

    /// @notice Register all facet selectors to the router
    function _registerAllSelectors() internal {
        // TradeFacet selectors
        bytes4[] memory tradeSelectors = new bytes4[](6);
        address[] memory tradeFacets = new address[](6);

        tradeSelectors[0] = TradeFacet.placeGridOrders.selector;
        tradeFacets[0] = tradeFacet;
        tradeSelectors[1] = TradeFacet.placeETHGridOrders.selector;
        tradeFacets[1] = tradeFacet;
        tradeSelectors[2] = TradeFacet.fillAskOrder.selector;
        tradeFacets[2] = tradeFacet;
        tradeSelectors[3] = TradeFacet.fillAskOrders.selector;
        tradeFacets[3] = tradeFacet;
        tradeSelectors[4] = TradeFacet.fillBidOrder.selector;
        tradeFacets[4] = tradeFacet;
        tradeSelectors[5] = TradeFacet.fillBidOrders.selector;
        tradeFacets[5] = tradeFacet;

        AdminFacet(router).batchSetFacet(tradeSelectors, tradeFacets);
        console.log("[OK] TradeFacet selectors registered");

        // CancelFacet selectors
        bytes4[] memory cancelSelectors = new bytes4[](5);
        address[] memory cancelFacets = new address[](5);

        cancelSelectors[0] = CancelFacet.cancelGrid.selector;
        cancelFacets[0] = cancelFacet;
        cancelSelectors[1] = bytes4(keccak256("cancelGridOrders(address,uint64,uint32,uint32)"));
        cancelFacets[1] = cancelFacet;
        cancelSelectors[2] = bytes4(keccak256("cancelGridOrders(uint48,address,uint64[],uint32)"));
        cancelFacets[2] = cancelFacet;
        cancelSelectors[3] = CancelFacet.withdrawGridProfits.selector;
        cancelFacets[3] = cancelFacet;
        cancelSelectors[4] = CancelFacet.modifyGridFee.selector;
        cancelFacets[4] = cancelFacet;

        AdminFacet(router).batchSetFacet(cancelSelectors, cancelFacets);
        console.log("[OK] CancelFacet selectors registered");

        // AdminFacet selectors (beyond bootstrap)
        bytes4[] memory adminSelectors = new bytes4[](9);
        address[] memory adminFacets = new address[](9);

        adminSelectors[0] = AdminFacet.setWETH.selector;
        adminFacets[0] = adminFacet;
        adminSelectors[1] = AdminFacet.setQuoteToken.selector;
        adminFacets[1] = adminFacet;
        adminSelectors[2] = AdminFacet.setStrategyWhitelist.selector;
        adminFacets[2] = adminFacet;
        adminSelectors[3] = AdminFacet.setOneshotProtocolFeeBps.selector;
        adminFacets[3] = adminFacet;
        adminSelectors[4] = AdminFacet.pause.selector;
        adminFacets[4] = adminFacet;
        adminSelectors[5] = AdminFacet.unpause.selector;
        adminFacets[5] = adminFacet;
        adminSelectors[6] = AdminFacet.rescueEth.selector;
        adminFacets[6] = adminFacet;
        adminSelectors[7] = AdminFacet.transferOwnership.selector;
        adminFacets[7] = adminFacet;
        adminSelectors[8] = AdminFacet.setFacet.selector;
        adminFacets[8] = adminFacet;

        AdminFacet(router).batchSetFacet(adminSelectors, adminFacets);
        console.log("[OK] AdminFacet selectors registered");

        // ViewFacet selectors
        bytes4[] memory viewSelectors = new bytes4[](12);
        address[] memory viewFacets = new address[](12);

        viewSelectors[0] = ViewFacet.getGridOrder.selector;
        viewFacets[0] = viewFacet;
        viewSelectors[1] = ViewFacet.getGridOrders.selector;
        viewFacets[1] = viewFacet;
        viewSelectors[2] = ViewFacet.getGridProfits.selector;
        viewFacets[2] = viewFacet;
        viewSelectors[3] = ViewFacet.getGridConfig.selector;
        viewFacets[3] = viewFacet;
        viewSelectors[4] = ViewFacet.getOneshotProtocolFeeBps.selector;
        viewFacets[4] = viewFacet;
        viewSelectors[5] = ViewFacet.isStrategyWhitelisted.selector;
        viewFacets[5] = viewFacet;
        viewSelectors[6] = ViewFacet.getPairTokens.selector;
        viewFacets[6] = viewFacet;
        viewSelectors[7] = ViewFacet.getPairIdByTokens.selector;
        viewFacets[7] = viewFacet;
        viewSelectors[8] = ViewFacet.paused.selector;
        viewFacets[8] = viewFacet;
        viewSelectors[9] = ViewFacet.owner.selector;
        viewFacets[9] = viewFacet;
        viewSelectors[10] = ViewFacet.vault.selector;
        viewFacets[10] = viewFacet;
        viewSelectors[11] = ViewFacet.WETH.selector;
        viewFacets[11] = viewFacet;

        AdminFacet(router).batchSetFacet(viewSelectors, viewFacets);
        console.log("[OK] ViewFacet selectors registered");
    }

    /// @notice Preview deployment addresses without deploying
    function preview() public view {
        (address weth, address usd) = _getTokenAddresses();

        console.log("========================================");
        console.log("Deployment Preview (Diamond)");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("WETH:", weth);
        console.log("USD:", usd);
        console.log("Salt:", vm.toString(DEPLOYMENT_SALT));
        console.log("");

        (
            address expectedVault,
            address expectedAdminFacet,
            address expectedTradeFacet,
            address expectedCancelFacet,
            address expectedViewFacet,
            address expectedRouter,
            address expectedLinear,
            address expectedGeometry
        ) = computeAddresses(weth, usd);

        console.log("Expected Addresses:");
        console.log("  Vault:", expectedVault);
        console.log("  AdminFacet:", expectedAdminFacet);
        console.log("  TradeFacet:", expectedTradeFacet);
        console.log("  CancelFacet:", expectedCancelFacet);
        console.log("  ViewFacet:", expectedViewFacet);
        console.log("  Router:", expectedRouter);
        console.log("  Linear:", expectedLinear);
        console.log("  Geometry:", expectedGeometry);
        console.log("");

        // Check if already deployed
        console.log("Deployment Status:");
        console.log("  Vault:", expectedVault.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
        console.log("  AdminFacet:", expectedAdminFacet.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
        console.log("  TradeFacet:", expectedTradeFacet.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
        console.log("  CancelFacet:", expectedCancelFacet.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
        console.log("  ViewFacet:", expectedViewFacet.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
        console.log("  Router:", expectedRouter.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
        console.log("  Linear:", expectedLinear.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
        console.log("  Geometry:", expectedGeometry.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
    }

    /// @notice Compute expected addresses for current deployer
    function computeAddresses(address, address)
        public
        view
        returns (
            address expectedVault,
            address expectedAdminFacet,
            address expectedTradeFacet,
            address expectedCancelFacet,
            address expectedViewFacet,
            address expectedRouter,
            address expectedLinear,
            address expectedGeometry
        )
    {
        // Get deployer address for computing addresses
        address deployer = vm.envOr("DEPLOYER_ADDRESS", address(0));
        if (deployer == address(0)) {
            try vm.envUint("PRIVATE_KEY") returns (uint256 pk) {
                deployer = vm.addr(pk);
            } catch {
                revert("DEPLOYER_ADDRESS or PRIVATE_KEY required");
            }
        }

        return computeAddressesWithOwner(deployer);
    }

    /// @notice Compute expected addresses for given owner
    /// @dev With diamond pattern, all facets have no constructor args.
    ///      Router constructor takes (owner, vault, adminFacet).
    function computeAddressesWithOwner(address _owner)
        public
        pure
        returns (
            address expectedVault,
            address expectedAdminFacet,
            address expectedTradeFacet,
            address expectedCancelFacet,
            address expectedViewFacet,
            address expectedRouter,
            address expectedLinear,
            address expectedGeometry
        )
    {
        // Vault (takes owner as constructor arg - same on all chains if same owner)
        bytes32 vaultSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Vault"));
        bytes memory vaultBytecode = abi.encodePacked(type(Vault).creationCode, abi.encode(_owner));
        expectedVault = _computeAddress(vaultSalt, vaultBytecode);

        // AdminFacet (no constructor args - same address everywhere)
        bytes32 adminFacetSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "AdminFacet"));
        bytes memory adminFacetBytecode = type(AdminFacet).creationCode;
        expectedAdminFacet = _computeAddress(adminFacetSalt, adminFacetBytecode);

        // TradeFacet (no constructor args - same address everywhere)
        bytes32 tradeFacetSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "TradeFacet"));
        bytes memory tradeFacetBytecode = type(TradeFacet).creationCode;
        expectedTradeFacet = _computeAddress(tradeFacetSalt, tradeFacetBytecode);

        // CancelFacet (no constructor args - same address everywhere)
        bytes32 cancelFacetSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "CancelFacet"));
        bytes memory cancelFacetBytecode = type(CancelFacet).creationCode;
        expectedCancelFacet = _computeAddress(cancelFacetSalt, cancelFacetBytecode);

        // ViewFacet (no constructor args - same address everywhere)
        bytes32 viewFacetSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "ViewFacet"));
        bytes memory viewFacetBytecode = type(ViewFacet).creationCode;
        expectedViewFacet = _computeAddress(viewFacetSalt, viewFacetBytecode);

        // Router (depends on owner, vault, adminFacet)
        bytes32 routerSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Router"));
        bytes memory routerBytecode =
            abi.encodePacked(type(GridExRouter).creationCode, abi.encode(_owner, expectedVault, expectedAdminFacet));
        expectedRouter = _computeAddress(routerSalt, routerBytecode);

        // Linear (depends on router address)
        bytes32 linearSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Linear"));
        bytes memory linearBytecode = abi.encodePacked(type(Linear).creationCode, abi.encode(expectedRouter));
        expectedLinear = _computeAddress(linearSalt, linearBytecode);

        // Geometry (depends on router address)
        bytes32 geometrySalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Geometry"));
        bytes memory geometryBytecode = abi.encodePacked(type(Geometry).creationCode, abi.encode(expectedRouter));
        expectedGeometry = _computeAddress(geometrySalt, geometryBytecode);
    }

    // ============ Internal Functions ============

    /// @notice Get WETH and USD addresses from env or chain config
    function _getTokenAddresses() internal view returns (address weth, address usd) {
        // Try environment variables first
        try vm.envAddress("WETH_ADDRESS") returns (address _weth) {
            weth = _weth;
        } catch {
            // Fall back to chain config
            DeployConfig.ChainConfig memory config = DeployConfig.getConfig(block.chainid);
            weth = config.weth;
        }

        try vm.envAddress("USD_ADDRESS") returns (address _usd) {
            usd = _usd;
        } catch {
            DeployConfig.ChainConfig memory config = DeployConfig.getConfig(block.chainid);
            usd = config.usd;
        }

        require(weth != address(0), "WETH address not configured");
        require(usd != address(0), "USD address not configured");
    }

    /// @notice Deploy a contract using CREATE2
    function _deployContract(bytes32 salt, bytes memory bytecode, string memory name)
        internal
        returns (address deployed)
    {
        address expected = _computeAddress(salt, bytecode);

        // Check if already deployed
        if (expected.code.length > 0) {
            console.log(string.concat("[SKIP] ", name, " already deployed at:"), expected);
            return expected;
        }

        // Deploy using CREATE2 deployer
        bytes memory deployData = abi.encodePacked(salt, bytecode);
        (bool success, bytes memory result) = CREATE2_DEPLOYER.call(deployData);
        require(success, string.concat(name, " deployment failed"));

        // The deterministic deployment proxy returns exactly 20 bytes (the address)
        require(result.length == 20, string.concat(name, " unexpected return length"));
        // forge-lint: disable-next-line(unsafe-typecast)
        assembly {
            deployed := mload(add(result, 20))
        }
        require(deployed == expected, string.concat(name, " address mismatch"));
        require(deployed.code.length > 0, string.concat(name, " deployment failed - no code"));

        console.log(string.concat("[OK] ", name, " deployed at:"), deployed);
    }

    /// @notice Compute CREATE2 address
    function _computeAddress(bytes32 salt, bytes memory bytecode) internal pure returns (address) {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, salt, keccak256(bytecode)))))
        );
    }

    /// @notice Print deployment summary
    function _printSummary(address weth, address usd) internal view {
        console.log("");
        console.log("========================================");
        console.log("Deployment Complete!");
        console.log("========================================");
        console.log("");
        console.log("Deployed Contracts:");
        console.log("  Vault:", vault);
        console.log("  AdminFacet:", adminFacet);
        console.log("  TradeFacet:", tradeFacet);
        console.log("  CancelFacet:", cancelFacet);
        console.log("  ViewFacet:", viewFacet);
        console.log("  Router:", router);
        console.log("  Linear:", linear);
        console.log("  Geometry:", geometry);
        console.log("");
        console.log("Configuration:");
        console.log("  WETH:", weth);
        console.log("  USD:", usd);
        console.log("  Owner:", ViewFacet(router).owner());
        console.log("");
        console.log("Verification Commands:");
        console.log("----------------------------------------");
        _printVerifyCommands();
    }

    /// @notice Print verification commands
    function _printVerifyCommands() internal view {
        string memory chainId = vm.toString(block.chainid);

        console.log("# Verify Vault");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(vault),
                " src/Vault.sol:Vault --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $(cast abi-encode 'constructor(address)' ",
                vm.toString(ViewFacet(router).owner()),
                ")"
            )
        );
        console.log("");

        console.log("# Verify AdminFacet (no constructor args)");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(adminFacet),
                " src/facets/AdminFacet.sol:AdminFacet --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY"
            )
        );
        console.log("");

        console.log("# Verify TradeFacet (no constructor args)");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(tradeFacet),
                " src/facets/TradeFacet.sol:TradeFacet --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY"
            )
        );
        console.log("");

        console.log("# Verify CancelFacet (no constructor args)");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(cancelFacet),
                " src/facets/CancelFacet.sol:CancelFacet --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY"
            )
        );
        console.log("");

        console.log("# Verify ViewFacet (no constructor args)");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(viewFacet),
                " src/facets/ViewFacet.sol:ViewFacet --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY"
            )
        );
        console.log("");

        console.log("# Verify Router");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(router),
                " src/GridExRouter.sol:GridExRouter --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $(cast abi-encode 'constructor(address,address,address)' ",
                vm.toString(ViewFacet(router).owner()),
                " ",
                vm.toString(vault),
                " ",
                vm.toString(adminFacet),
                ")"
            )
        );
        console.log("");

        console.log("# Verify Linear");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(linear),
                " src/strategy/Linear.sol:Linear --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $(cast abi-encode 'constructor(address)' ",
                vm.toString(router),
                ")"
            )
        );
        console.log("");

        console.log("# Verify Geometry");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(geometry),
                " src/strategy/Geometry.sol:Geometry --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $(cast abi-encode 'constructor(address)' ",
                vm.toString(router),
                ")"
            )
        );
    }
}
