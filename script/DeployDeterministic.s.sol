// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {Script, console2 as console} from "forge-std/Script.sol";

import {GridExRouter} from "../src/GridExRouter.sol";
import {TradeFacet} from "../src/facets/TradeFacet.sol";
import {CancelFacet} from "../src/facets/CancelFacet.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {ViewFacet} from "../src/facets/ViewFacet.sol";
import {Vault} from "../src/Vault.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {ProtocolConstants} from "../src/libraries/ProtocolConstants.sol";

/// @title DeployDeterministic
/// @notice Deterministic deployment script for GridEx protocol using diamond architecture
/// @dev Uses CREATE2 to deploy contracts to the same address across all chains
///
/// IMPORTANT: For contracts to have the same address across chains:
/// 1. The CREATE2 deployer must be at the same address on all chains
/// 2. The salt must be the same
/// 3. The bytecode (including constructor args) must be identical
///
/// GridEx uses a diamond pattern:
/// - Router: Constructor args include (owner, vault, adminFacet)
/// - Facets: No constructor args, deployed with CREATE2 → same address everywhere
/// - Chain-specific config (WETH, quote tokens) is set via setWETH() and setQuoteToken()
///   after deployment
///
/// To achieve same router address across chains, you need:
/// - Same owner address (deployer)
/// - Same vault address (deployed with CREATE2)
/// - Same adminFacet address (deployed with CREATE2)
contract DeployDeterministic is Script {
    // ============ Configuration ============

    /// @notice The salt used for CREATE2 deployment - MUST be the same across all chains
    /// @dev Change this salt to deploy to a different address
    bytes32 public constant DEPLOYMENT_SALT = keccak256("GridEx.V1.Production.2024.Diamond");

    /// @notice Foundry's default CREATE2 deployer (available on most chains)
    /// @dev This is deployed at the same address on all EVM chains via keyless deployment
    /// @dev See: https://github.com/Arachnid/deterministic-deployment-proxy
    address public constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // ============ Deployed Addresses ============
    address public deployedVault;
    address public deployedAdminFacet;
    address public deployedTradeFacet;
    address public deployedCancelFacet;
    address public deployedViewFacet;
    address public deployedRouter;
    address public deployedLinear;

    function setUp() public {}

    /// @notice Main deployment function
    /// @dev Reads configuration from environment variables
    function run() public {
        // Load configuration from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address weth = vm.envAddress("WETH_ADDRESS");
        address usd = vm.envAddress("USD_ADDRESS");

        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== GridEx Deterministic Deployment (Diamond) ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("WETH:", weth);
        console.log("USD:", usd);
        console.log("Salt:", vm.toString(DEPLOYMENT_SALT));
        console.log("");

        // Preview addresses (same on all chains — no WETH/USD dependency)
        (
            address expectedVault,
            address expectedAdminFacet,
            address expectedTradeFacet,
            address expectedCancelFacet,
            address expectedViewFacet,
            address expectedRouter,
            address expectedLinear
        ) = previewAddresses(deployer);

        console.log("Expected Addresses (same on all chains):");
        console.log("  Vault:", expectedVault);
        console.log("  AdminFacet:", expectedAdminFacet);
        console.log("  TradeFacet:", expectedTradeFacet);
        console.log("  CancelFacet:", expectedCancelFacet);
        console.log("  ViewFacet:", expectedViewFacet);
        console.log("  Router:", expectedRouter);
        console.log("  Linear:", expectedLinear);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy Vault (same address on all chains with same owner)
        deployedVault = _deployVault(deployer);
        require(deployedVault == expectedVault, "Vault address mismatch");
        console.log("[OK] Vault deployed at:", deployedVault);

        // Step 2: Deploy AdminFacet (no constructor args - same everywhere)
        deployedAdminFacet = _deployAdminFacet();
        require(deployedAdminFacet == expectedAdminFacet, "AdminFacet address mismatch");
        console.log("[OK] AdminFacet deployed at:", deployedAdminFacet);

        // Step 3: Deploy TradeFacet (no constructor args - same everywhere)
        deployedTradeFacet = _deployTradeFacet();
        require(deployedTradeFacet == expectedTradeFacet, "TradeFacet address mismatch");
        console.log("[OK] TradeFacet deployed at:", deployedTradeFacet);

        // Step 4: Deploy CancelFacet (no constructor args - same everywhere)
        deployedCancelFacet = _deployCancelFacet();
        require(deployedCancelFacet == expectedCancelFacet, "CancelFacet address mismatch");
        console.log("[OK] CancelFacet deployed at:", deployedCancelFacet);

        // Step 5: Deploy ViewFacet (no constructor args - same everywhere)
        deployedViewFacet = _deployViewFacet();
        require(deployedViewFacet == expectedViewFacet, "ViewFacet address mismatch");
        console.log("[OK] ViewFacet deployed at:", deployedViewFacet);

        // Step 6: Deploy Router (with admin facet for bootstrapping)
        deployedRouter = _deployRouter(deployer, deployedVault, deployedAdminFacet);
        require(deployedRouter == expectedRouter, "Router address mismatch");
        console.log("[OK] Router deployed at:", deployedRouter);

        // Step 7: Register all facet selectors
        _registerAllSelectors();
        console.log("[OK] All facet selectors registered");

        // Step 8: Configure chain-specific WETH and quote tokens
        AdminFacet(deployedRouter).setWETH(weth);
        console.log("[OK] WETH configured:", weth);

        AdminFacet(deployedRouter).setQuoteToken(Currency.wrap(usd), ProtocolConstants.QUOTE_PRIORITY_USD);
        console.log("[OK] USD quote token configured:", usd);

        AdminFacet(deployedRouter).setQuoteToken(Currency.wrap(weth), ProtocolConstants.QUOTE_PRIORITY_WETH);
        console.log("[OK] WETH quote token configured");

        // Step 9: Deploy Linear Strategy
        deployedLinear = _deployLinear(deployedRouter);
        require(deployedLinear == expectedLinear, "Linear address mismatch");
        console.log("[OK] Linear deployed at:", deployedLinear);

        // Step 10: Whitelist Linear strategy in Router
        if (!ViewFacet(deployedRouter).isStrategyWhitelisted(deployedLinear)) {
            AdminFacet(deployedRouter).setStrategyWhitelist(deployedLinear, true);
            console.log("[OK] Linear strategy whitelisted");
        } else {
            console.log("[SKIP] Linear already whitelisted");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        _printDeploymentSummary();
    }

    /// @notice Register all facet selectors to the router
    function _registerAllSelectors() internal {
        // TradeFacet selectors
        bytes4[] memory tradeSelectors = new bytes4[](6);
        address[] memory tradeFacets = new address[](6);

        tradeSelectors[0] = TradeFacet.placeGridOrders.selector;
        tradeFacets[0] = deployedTradeFacet;
        tradeSelectors[1] = TradeFacet.placeETHGridOrders.selector;
        tradeFacets[1] = deployedTradeFacet;
        tradeSelectors[2] = TradeFacet.fillAskOrder.selector;
        tradeFacets[2] = deployedTradeFacet;
        tradeSelectors[3] = TradeFacet.fillAskOrders.selector;
        tradeFacets[3] = deployedTradeFacet;
        tradeSelectors[4] = TradeFacet.fillBidOrder.selector;
        tradeFacets[4] = deployedTradeFacet;
        tradeSelectors[5] = TradeFacet.fillBidOrders.selector;
        tradeFacets[5] = deployedTradeFacet;

        AdminFacet(deployedRouter).batchSetFacet(tradeSelectors, tradeFacets);

        // CancelFacet selectors
        bytes4[] memory cancelSelectors = new bytes4[](5);
        address[] memory cancelFacets = new address[](5);

        cancelSelectors[0] = CancelFacet.cancelGrid.selector;
        cancelFacets[0] = deployedCancelFacet;
        cancelSelectors[1] = bytes4(keccak256("cancelGridOrders(address,uint256,uint32,uint32)"));
        cancelFacets[1] = deployedCancelFacet;
        cancelSelectors[2] = bytes4(keccak256("cancelGridOrders(uint128,address,uint256[],uint32)"));
        cancelFacets[2] = deployedCancelFacet;
        cancelSelectors[3] = CancelFacet.withdrawGridProfits.selector;
        cancelFacets[3] = deployedCancelFacet;
        cancelSelectors[4] = CancelFacet.modifyGridFee.selector;
        cancelFacets[4] = deployedCancelFacet;

        AdminFacet(deployedRouter).batchSetFacet(cancelSelectors, cancelFacets);

        // AdminFacet selectors (beyond bootstrap)
        bytes4[] memory adminSelectors = new bytes4[](9);
        address[] memory adminFacets = new address[](9);

        adminSelectors[0] = AdminFacet.setWETH.selector;
        adminFacets[0] = deployedAdminFacet;
        adminSelectors[1] = AdminFacet.setQuoteToken.selector;
        adminFacets[1] = deployedAdminFacet;
        adminSelectors[2] = AdminFacet.setStrategyWhitelist.selector;
        adminFacets[2] = deployedAdminFacet;
        adminSelectors[3] = AdminFacet.setOneshotProtocolFeeBps.selector;
        adminFacets[3] = deployedAdminFacet;
        adminSelectors[4] = AdminFacet.pause.selector;
        adminFacets[4] = deployedAdminFacet;
        adminSelectors[5] = AdminFacet.unpause.selector;
        adminFacets[5] = deployedAdminFacet;
        adminSelectors[6] = AdminFacet.rescueEth.selector;
        adminFacets[6] = deployedAdminFacet;
        adminSelectors[7] = AdminFacet.transferOwnership.selector;
        adminFacets[7] = deployedAdminFacet;
        adminSelectors[8] = AdminFacet.setFacet.selector;
        adminFacets[8] = deployedAdminFacet;

        AdminFacet(deployedRouter).batchSetFacet(adminSelectors, adminFacets);

        // ViewFacet selectors
        bytes4[] memory viewSelectors = new bytes4[](12);
        address[] memory viewFacets = new address[](12);

        viewSelectors[0] = ViewFacet.getGridOrder.selector;
        viewFacets[0] = deployedViewFacet;
        viewSelectors[1] = ViewFacet.getGridOrders.selector;
        viewFacets[1] = deployedViewFacet;
        viewSelectors[2] = ViewFacet.getGridProfits.selector;
        viewFacets[2] = deployedViewFacet;
        viewSelectors[3] = ViewFacet.getGridConfig.selector;
        viewFacets[3] = deployedViewFacet;
        viewSelectors[4] = ViewFacet.getOneshotProtocolFeeBps.selector;
        viewFacets[4] = deployedViewFacet;
        viewSelectors[5] = ViewFacet.isStrategyWhitelisted.selector;
        viewFacets[5] = deployedViewFacet;
        viewSelectors[6] = ViewFacet.getPairTokens.selector;
        viewFacets[6] = deployedViewFacet;
        viewSelectors[7] = ViewFacet.getPairIdByTokens.selector;
        viewFacets[7] = deployedViewFacet;
        viewSelectors[8] = ViewFacet.paused.selector;
        viewFacets[8] = deployedViewFacet;
        viewSelectors[9] = ViewFacet.owner.selector;
        viewFacets[9] = deployedViewFacet;
        viewSelectors[10] = ViewFacet.vault.selector;
        viewFacets[10] = deployedViewFacet;
        viewSelectors[11] = ViewFacet.WETH.selector;
        viewFacets[11] = deployedViewFacet;

        AdminFacet(deployedRouter).batchSetFacet(viewSelectors, viewFacets);
    }

    /// @notice Deploy only Vault
    function deployVaultOnly() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        deployedVault = _deployVault(deployer);
        vm.stopBroadcast();

        console.log("Vault deployed at:", deployedVault);
    }

    /// @notice Deploy Vault using CREATE2
    /// @param _owner The owner address for the Vault
    function _deployVault(address _owner) internal returns (address) {
        bytes memory bytecode = abi.encodePacked(type(Vault).creationCode, abi.encode(_owner));
        bytes32 salt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Vault"));

        return _create2Deploy(salt, bytecode);
    }

    /// @notice Deploy AdminFacet using CREATE2 (no constructor args)
    function _deployAdminFacet() internal returns (address) {
        bytes memory bytecode = type(AdminFacet).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "AdminFacet"));

        return _create2Deploy(salt, bytecode);
    }

    /// @notice Deploy TradeFacet using CREATE2 (no constructor args)
    function _deployTradeFacet() internal returns (address) {
        bytes memory bytecode = type(TradeFacet).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "TradeFacet"));

        return _create2Deploy(salt, bytecode);
    }

    /// @notice Deploy CancelFacet using CREATE2 (no constructor args)
    function _deployCancelFacet() internal returns (address) {
        bytes memory bytecode = type(CancelFacet).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "CancelFacet"));

        return _create2Deploy(salt, bytecode);
    }

    /// @notice Deploy ViewFacet using CREATE2 (no constructor args)
    function _deployViewFacet() internal returns (address) {
        bytes memory bytecode = type(ViewFacet).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "ViewFacet"));

        return _create2Deploy(salt, bytecode);
    }

    /// @notice Deploy Router using CREATE2
    /// @param _owner The owner address for the Router
    /// @param _vault The vault address for protocol fees
    /// @param _adminFacet The admin facet address for bootstrapping
    function _deployRouter(address _owner, address _vault, address _adminFacet) internal returns (address) {
        bytes memory bytecode =
            abi.encodePacked(type(GridExRouter).creationCode, abi.encode(_owner, _vault, _adminFacet));
        bytes32 salt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Router"));

        return _create2Deploy(salt, bytecode);
    }

    /// @notice Deploy Linear strategy using CREATE2
    function _deployLinear(address _router) internal returns (address) {
        bytes memory bytecode = abi.encodePacked(type(Linear).creationCode, abi.encode(_router));
        bytes32 salt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Linear"));

        return _create2Deploy(salt, bytecode);
    }

    /// @notice Internal function to deploy using CREATE2
    /// @dev Uses the deterministic deployment proxy
    function _create2Deploy(bytes32 salt, bytes memory bytecode) internal returns (address deployed) {
        // Check if CREATE2 deployer exists
        require(CREATE2_DEPLOYER.code.length > 0, "CREATE2 deployer not found on this chain");

        // Compute expected address
        address expected = _computeAddress(salt, bytecode);

        // Check if already deployed
        if (expected.code.length > 0) {
            console.log("Contract already deployed at:", expected);
            return expected;
        }

        // Deploy using CREATE2
        // The deployer expects: salt (32 bytes) + bytecode
        bytes memory deployData = abi.encodePacked(salt, bytecode);

        (bool success, bytes memory result) = CREATE2_DEPLOYER.call(deployData);
        require(success, "CREATE2 deployment failed");

        // The deterministic deployment proxy returns exactly 20 bytes (the address)
        require(result.length == 20, "Unexpected return length from CREATE2 deployer");
        // forge-lint: disable-next-line(unsafe-typecast)
        assembly {
            deployed := mload(add(result, 20))
        }

        // Verify deployment
        require(deployed == expected, "Deployed address mismatch");
        require(deployed.code.length > 0, "Deployment failed - no code at address");
    }

    /// @notice Compute the expected address for a contract
    function _computeAddress(bytes32 salt, bytes memory bytecode) internal pure returns (address) {
        bytes32 bytecodeHash = keccak256(bytecode);
        return
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, salt, bytecodeHash)))));
    }

    /// @notice Preview deployment addresses without actually deploying
    /// @dev Only requires owner — WETH/USD no longer affect router address
    function previewAddresses(address _owner)
        public
        pure
        returns (
            address expectedVault,
            address expectedAdminFacet,
            address expectedTradeFacet,
            address expectedCancelFacet,
            address expectedViewFacet,
            address expectedRouter,
            address expectedLinear
        )
    {
        // Compute Vault address (depends on owner)
        bytes memory vaultBytecode = abi.encodePacked(type(Vault).creationCode, abi.encode(_owner));
        bytes32 vaultSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Vault"));
        expectedVault = _computeAddress(vaultSalt, vaultBytecode);

        // Compute AdminFacet address (no constructor args - same everywhere)
        bytes memory adminFacetBytecode = type(AdminFacet).creationCode;
        bytes32 adminFacetSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "AdminFacet"));
        expectedAdminFacet = _computeAddress(adminFacetSalt, adminFacetBytecode);

        // Compute TradeFacet address (no constructor args - same everywhere)
        bytes memory tradeFacetBytecode = type(TradeFacet).creationCode;
        bytes32 tradeFacetSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "TradeFacet"));
        expectedTradeFacet = _computeAddress(tradeFacetSalt, tradeFacetBytecode);

        // Compute CancelFacet address (no constructor args - same everywhere)
        bytes memory cancelFacetBytecode = type(CancelFacet).creationCode;
        bytes32 cancelFacetSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "CancelFacet"));
        expectedCancelFacet = _computeAddress(cancelFacetSalt, cancelFacetBytecode);

        // Compute ViewFacet address (no constructor args - same everywhere)
        bytes memory viewFacetBytecode = type(ViewFacet).creationCode;
        bytes32 viewFacetSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "ViewFacet"));
        expectedViewFacet = _computeAddress(viewFacetSalt, viewFacetBytecode);

        // Compute Router address (depends on owner, vault, adminFacet)
        bytes memory routerBytecode =
            abi.encodePacked(type(GridExRouter).creationCode, abi.encode(_owner, expectedVault, expectedAdminFacet));
        bytes32 routerSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Router"));
        expectedRouter = _computeAddress(routerSalt, routerBytecode);

        // Compute Linear address (depends on router)
        bytes memory linearBytecode = abi.encodePacked(type(Linear).creationCode, abi.encode(expectedRouter));
        bytes32 linearSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Linear"));
        expectedLinear = _computeAddress(linearSalt, linearBytecode);
    }

    /// @notice Preview addresses from environment
    function preview() public view {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Deployment Preview (Diamond) ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer/Owner:", deployer);
        console.log("");

        (
            address expectedVault,
            address expectedAdminFacet,
            address expectedTradeFacet,
            address expectedCancelFacet,
            address expectedViewFacet,
            address expectedRouter,
            address expectedLinear
        ) = previewAddresses(deployer);

        console.log("Expected Addresses (same on all chains):");
        console.log("  Vault:", expectedVault);
        console.log("  AdminFacet:", expectedAdminFacet);
        console.log("  TradeFacet:", expectedTradeFacet);
        console.log("  CancelFacet:", expectedCancelFacet);
        console.log("  ViewFacet:", expectedViewFacet);
        console.log("  Router:", expectedRouter);
        console.log("  Linear:", expectedLinear);
    }

    function _printDeploymentSummary() internal view {
        console.log("Deployed Contracts:");
        console.log("  Vault:", deployedVault);
        console.log("  AdminFacet:", deployedAdminFacet);
        console.log("  TradeFacet:", deployedTradeFacet);
        console.log("  CancelFacet:", deployedCancelFacet);
        console.log("  ViewFacet:", deployedViewFacet);
        console.log("  Router:", deployedRouter);
        console.log("  Linear:", deployedLinear);
        console.log("");
        console.log("Next Steps:");
        console.log("  1. Verify contracts on block explorer");
        console.log("  2. Transfer Vault ownership if needed");
        console.log("  3. Transfer Router ownership if needed");
        console.log("  4. To upgrade: deploy new facets and update selectors");
    }
}
