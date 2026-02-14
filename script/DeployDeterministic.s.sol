// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {Script, console2 as console} from "forge-std/Script.sol";

import {GridEx} from "../src/GridEx.sol";
import {Vault} from "../src/Vault.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {ProtocolConstants} from "../src/libraries/ProtocolConstants.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DeployDeterministic
/// @notice Deterministic deployment script for GridEx protocol using UUPS proxy
/// @dev Uses CREATE2 to deploy contracts to the same address across all chains
///
/// IMPORTANT: For contracts to have the same address across chains:
/// 1. The CREATE2 deployer must be at the same address on all chains
/// 2. The salt must be the same
/// 3. The bytecode (including constructor args) must be identical
///
/// GridEx uses a UUPS proxy pattern:
/// - Implementation: No constructor args, deployed with CREATE2 → same address everywhere
/// - Proxy: Constructor args include (impl, initData). initData encodes only (owner, vault).
///   Chain-specific config (WETH, quote tokens) is set via setWETH() and setQuoteToken()
///   after deployment, so the proxy address is identical across all chains.
///
/// To achieve same proxy address across chains, you need:
/// - Same owner address (deployer)
/// - Same vault address (deployed with CREATE2)
contract DeployDeterministic is Script {
    // ============ Configuration ============

    /// @notice The salt used for CREATE2 deployment - MUST be the same across all chains
    /// @dev Change this salt to deploy to a different address
    bytes32 public constant DEPLOYMENT_SALT = keccak256("GridEx.V1.Production.2024");

    /// @notice Foundry's default CREATE2 deployer (available on most chains)
    /// @dev This is deployed at the same address on all EVM chains via keyless deployment
    /// @dev See: https://github.com/Arachnid/deterministic-deployment-proxy
    address public constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // ============ Deployed Addresses ============
    address public deployedVault;
    address public deployedGridExImpl;
    address public deployedGridEx; // proxy address
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

        console.log("=== GridEx Deterministic Deployment (UUPS Proxy) ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("WETH:", weth);
        console.log("USD:", usd);
        console.log("Salt:", vm.toString(DEPLOYMENT_SALT));
        console.log("");

        // Preview addresses (same on all chains — no WETH/USD dependency)
        (address expectedVault, address expectedImpl, address expectedProxy, address expectedLinear) =
            previewAddresses(deployer);

        console.log("Expected Addresses (same on all chains):");
        console.log("  Vault:", expectedVault);
        console.log("  GridEx Impl:", expectedImpl);
        console.log("  GridEx Proxy:", expectedProxy);
        console.log("  Linear:", expectedLinear);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy Vault (same address on all chains with same owner)
        deployedVault = _deployVault(deployer);
        require(deployedVault == expectedVault, "Vault address mismatch");
        console.log("[OK] Vault deployed at:", deployedVault);

        // Step 2: Deploy GridEx implementation (no constructor args - same everywhere)
        deployedGridExImpl = _deployGridExImpl();
        require(deployedGridExImpl == expectedImpl, "GridEx impl address mismatch");
        console.log("[OK] GridEx impl deployed at:", deployedGridExImpl);

        // Step 3: Deploy ERC1967Proxy with initialize() call (chain-agnostic)
        deployedGridEx = _deployGridExProxy(deployer, deployedVault);
        require(deployedGridEx == expectedProxy, "GridEx proxy address mismatch");
        console.log("[OK] GridEx proxy deployed at:", deployedGridEx);

        // Step 4: Configure chain-specific WETH and quote tokens
        GridEx(payable(deployedGridEx)).setWETH(weth);
        console.log("[OK] WETH configured:", weth);

        GridEx(payable(deployedGridEx)).setQuoteToken(Currency.wrap(usd), ProtocolConstants.QUOTE_PRIORITY_USD);
        console.log("[OK] USD quote token configured:", usd);

        GridEx(payable(deployedGridEx)).setQuoteToken(Currency.wrap(weth), ProtocolConstants.QUOTE_PRIORITY_WETH);
        console.log("[OK] WETH quote token configured");

        // Step 5: Deploy Linear Strategy
        deployedLinear = _deployLinear(deployedGridEx);
        require(deployedLinear == expectedLinear, "Linear address mismatch");
        console.log("[OK] Linear deployed at:", deployedLinear);

        // Step 6: Whitelist Linear strategy in GridEx
        if (!GridEx(payable(deployedGridEx)).whitelistedStrategies(deployedLinear)) {
            GridEx(payable(deployedGridEx)).setStrategyWhitelist(deployedLinear, true);
            console.log("[OK] Linear strategy whitelisted");
        } else {
            console.log("[SKIP] Linear already whitelisted");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        _printDeploymentSummary();
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

    /// @notice Deploy GridEx and Linear (requires Vault to be deployed)
    function deployGridExOnly() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address weth = vm.envAddress("WETH_ADDRESS");
        address usd = vm.envAddress("USD_ADDRESS");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        deployedGridExImpl = _deployGridExImpl();
        console.log("GridEx impl deployed at:", deployedGridExImpl);

        // Deploy proxy (chain-agnostic initialization)
        deployedGridEx = _deployGridExProxy(deployer, vaultAddr);
        console.log("GridEx proxy deployed at:", deployedGridEx);

        // Configure chain-specific settings
        GridEx(payable(deployedGridEx)).setWETH(weth);
        GridEx(payable(deployedGridEx)).setQuoteToken(Currency.wrap(usd), ProtocolConstants.QUOTE_PRIORITY_USD);
        GridEx(payable(deployedGridEx)).setQuoteToken(Currency.wrap(weth), ProtocolConstants.QUOTE_PRIORITY_WETH);
        console.log("GridEx configured with WETH and quote tokens");

        deployedLinear = _deployLinear(deployedGridEx);
        console.log("Linear deployed at:", deployedLinear);

        GridEx(payable(deployedGridEx)).setStrategyWhitelist(deployedLinear, true);
        console.log("Linear strategy whitelisted");

        vm.stopBroadcast();
    }

    /// @notice Deploy Vault using CREATE2
    /// @param _owner The owner address for the Vault
    function _deployVault(address _owner) internal returns (address) {
        bytes memory bytecode = abi.encodePacked(type(Vault).creationCode, abi.encode(_owner));
        bytes32 salt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Vault"));

        return _create2Deploy(salt, bytecode);
    }

    /// @notice Deploy GridEx implementation using CREATE2 (no constructor args)
    function _deployGridExImpl() internal returns (address) {
        bytes memory bytecode = type(GridEx).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "GridExImpl"));

        return _create2Deploy(salt, bytecode);
    }

    /// @notice Deploy ERC1967Proxy for GridEx using CREATE2
    /// @dev initData only encodes (owner, vault) — no chain-specific args.
    ///      WETH and quote tokens are configured post-deployment via setWETH() / setQuoteToken().
    /// @param _owner The owner address for GridEx
    /// @param _vault The vault address for protocol fees
    function _deployGridExProxy(address _owner, address _vault) internal returns (address) {
        bytes memory initData = abi.encodeCall(GridEx.initialize, (_owner, _vault));
        bytes memory bytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(deployedGridExImpl, initData));
        bytes32 salt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "GridExProxy"));

        return _create2Deploy(salt, bytecode);
    }

    /// @notice Deploy Linear strategy using CREATE2
    function _deployLinear(address _gridEx) internal returns (address) {
        bytes memory bytecode = abi.encodePacked(type(Linear).creationCode, abi.encode(_gridEx));
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
    /// @dev Only requires owner — WETH/USD no longer affect proxy address
    function previewAddresses(address _owner)
        public
        pure
        returns (address expectedVault, address expectedImpl, address expectedProxy, address expectedLinear)
    {
        // Compute Vault address (depends on owner)
        bytes memory vaultBytecode = abi.encodePacked(type(Vault).creationCode, abi.encode(_owner));
        bytes32 vaultSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Vault"));
        expectedVault = _computeAddress(vaultSalt, vaultBytecode);

        // Compute GridEx implementation address (no constructor args - same everywhere)
        bytes memory implBytecode = type(GridEx).creationCode;
        bytes32 implSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "GridExImpl"));
        expectedImpl = _computeAddress(implSalt, implBytecode);

        // Compute GridEx proxy address (depends only on impl, owner, vault — same across all chains)
        bytes memory initData = abi.encodeCall(GridEx.initialize, (_owner, expectedVault));
        bytes memory proxyBytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(expectedImpl, initData));
        bytes32 proxySalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "GridExProxy"));
        expectedProxy = _computeAddress(proxySalt, proxyBytecode);

        // Compute Linear address (depends on proxy)
        bytes memory linearBytecode = abi.encodePacked(type(Linear).creationCode, abi.encode(expectedProxy));
        bytes32 linearSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Linear"));
        expectedLinear = _computeAddress(linearSalt, linearBytecode);
    }

    /// @notice Preview addresses from environment
    function preview() public view {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Deployment Preview (UUPS Proxy) ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer/Owner:", deployer);
        console.log("");

        (address expectedVault, address expectedImpl, address expectedProxy, address expectedLinear) =
            previewAddresses(deployer);

        console.log("Expected Addresses (same on all chains):");
        console.log("  Vault:", expectedVault);
        console.log("  GridEx Impl:", expectedImpl);
        console.log("  GridEx Proxy:", expectedProxy);
        console.log("  Linear:", expectedLinear);
    }

    function _printDeploymentSummary() internal view {
        console.log("Deployed Contracts:");
        console.log("  Vault:", deployedVault);
        console.log("  GridEx Impl:", deployedGridExImpl);
        console.log("  GridEx Proxy:", deployedGridEx);
        console.log("  Linear:", deployedLinear);
        console.log("");
        console.log("Next Steps:");
        console.log("  1. Verify contracts on block explorer");
        console.log("  2. Transfer Vault ownership if needed");
        console.log("  3. Transfer GridEx ownership if needed");
        console.log("  4. To upgrade GridEx: deploy new impl, call upgradeToAndCall()");
    }
}
