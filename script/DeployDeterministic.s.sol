// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {Script, console2 as console} from "forge-std/Script.sol";

import {GridEx} from "../src/GridEx.sol";
import {Vault} from "../src/Vault.sol";
import {Linear} from "../src/strategy/Linear.sol";

/// @title DeployDeterministic
/// @notice Deterministic deployment script for GridEx protocol
/// @dev Uses CREATE2 to deploy contracts to the same address across all chains
///
/// IMPORTANT: For contracts to have the same address across chains:
/// 1. The CREATE2 deployer must be at the same address on all chains
/// 2. The salt must be the same
/// 3. The bytecode (including constructor args) must be identical
///
/// For GridEx, since constructor args include WETH/USD addresses which differ per chain,
/// we use a two-phase approach:
/// - Phase 1: Deploy Vault (no constructor args) - same address everywhere
/// - Phase 2: Deploy GridEx with chain-specific WETH/USD - different addresses per chain
///
/// To achieve same GridEx address across chains, you need:
/// - Same WETH address on all chains (deploy your own WETH with CREATE2)
/// - Same USD address on all chains (deploy your own USD with CREATE2)
/// - Or use a proxy pattern where the proxy has no constructor args
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
    address public deployedGridEx;
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

        console.log("=== GridEx Deterministic Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("WETH:", weth);
        console.log("USD:", usd);
        console.log("Salt:", vm.toString(DEPLOYMENT_SALT));
        console.log("");

        // Preview addresses first (now only depends on owner, not WETH/USD)
        (address expectedVault, address expectedGridEx, address expectedLinear) = previewAddresses(deployer);

        console.log("Expected Addresses:");
        console.log("  Vault:", expectedVault);
        console.log("  GridEx:", expectedGridEx);
        console.log("  Linear:", expectedLinear);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy Vault (same address on all chains with same owner)
        deployedVault = _deployVault(deployer);
        require(deployedVault == expectedVault, "Vault address mismatch");
        console.log("[OK] Vault deployed at:", deployedVault);

        // Step 2: Deploy GridEx (same address on all chains with same owner)
        deployedGridEx = _deployGridEx(deployer, deployedVault);
        require(deployedGridEx == expectedGridEx, "GridEx address mismatch");
        console.log("[OK] GridEx deployed at:", deployedGridEx);

        // Step 3: Initialize GridEx with chain-specific WETH/USD
        if (!GridEx(payable(deployedGridEx)).initialized()) {
            GridEx(payable(deployedGridEx)).initialize(weth, usd);
            console.log("[OK] GridEx initialized with WETH:", weth, "USD:", usd);
        } else {
            console.log("[SKIP] GridEx already initialized");
        }

        // Step 4: Deploy Linear Strategy
        deployedLinear = _deployLinear(deployedGridEx);
        require(deployedLinear == expectedLinear, "Linear address mismatch");
        console.log("[OK] Linear deployed at:", deployedLinear);

        // Step 5: Whitelist Linear strategy in GridEx
        GridEx(payable(deployedGridEx)).setStrategyWhitelist(deployedLinear, true);
        console.log("[OK] Linear strategy whitelisted");

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
        address vault = vm.envAddress("VAULT_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        deployedGridEx = _deployGridEx(deployer, vault);
        console.log("GridEx deployed at:", deployedGridEx);

        // Initialize with chain-specific WETH/USD
        if (!GridEx(payable(deployedGridEx)).initialized()) {
            GridEx(payable(deployedGridEx)).initialize(weth, usd);
            console.log("GridEx initialized");
        }

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

    /// @notice Deploy GridEx using CREATE2
    /// @param _owner The owner address for GridEx
    /// @param _vault The vault address for protocol fees
    function _deployGridEx(address _owner, address _vault) internal returns (address) {
        bytes memory bytecode = abi.encodePacked(type(GridEx).creationCode, abi.encode(_owner, _vault));
        bytes32 salt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "GridEx"));

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
    /// @dev WETH/USD are no longer needed for address computation since they're set via initialize()
    function previewAddresses(address _owner)
        public
        pure
        returns (address expectedVault, address expectedGridEx, address expectedLinear)
    {
        // Compute Vault address (depends on owner)
        bytes memory vaultBytecode = abi.encodePacked(type(Vault).creationCode, abi.encode(_owner));
        bytes32 vaultSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Vault"));
        expectedVault = _computeAddress(vaultSalt, vaultBytecode);

        // Compute GridEx address (depends on owner and vault)
        bytes memory gridExBytecode = abi.encodePacked(type(GridEx).creationCode, abi.encode(_owner, expectedVault));
        bytes32 gridExSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "GridEx"));
        expectedGridEx = _computeAddress(gridExSalt, gridExBytecode);

        // Compute Linear address (depends on gridEx)
        bytes memory linearBytecode = abi.encodePacked(type(Linear).creationCode, abi.encode(expectedGridEx));
        bytes32 linearSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Linear"));
        expectedLinear = _computeAddress(linearSalt, linearBytecode);
    }

    /// @notice Preview addresses from environment
    function preview() public view {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address _weth = vm.envAddress("WETH_ADDRESS");
        address _usd = vm.envAddress("USD_ADDRESS");

        console.log("=== Deployment Preview ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer/Owner:", deployer);
        console.log("WETH:", _weth);
        console.log("USD:", _usd);
        console.log("");

        (address expectedVault, address expectedGridEx, address expectedLinear) = previewAddresses(deployer);

        console.log("Expected Addresses (same on all chains with same owner):");
        console.log("  Vault:", expectedVault);
        console.log("  GridEx:", expectedGridEx);
        console.log("  Linear:", expectedLinear);
    }

    function _printDeploymentSummary() internal view {
        console.log("Deployed Contracts:");
        console.log("  Vault:", deployedVault);
        console.log("  GridEx:", deployedGridEx);
        console.log("  Linear:", deployedLinear);
        console.log("");
        console.log("Next Steps:");
        console.log("  1. Verify contracts on block explorer");
        console.log("  2. Transfer Vault ownership if needed");
        console.log("  3. Transfer GridEx ownership if needed");
    }
}
