// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";

import {GridEx} from "../src/GridEx.sol";
import {Vault} from "../src/Vault.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {DeployConfig} from "./config/DeployConfig.sol";

/// @title Deploy
/// @notice Production deployment script for GridEx protocol with deterministic addresses
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
/// Since GridEx constructor takes WETH/USD addresses which differ per chain,
/// we have two options:
///
/// Option A: Deploy canonical WETH/USD first using CREATE2 (same addresses everywhere)
/// Option B: Use a proxy pattern where the implementation has no constructor args
///
/// This script implements Option A - it can deploy canonical tokens first,
/// then deploy GridEx with those canonical addresses.
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
    bytes32 public constant DEPLOYMENT_SALT = keccak256("GridEx.V1.2024.Production");

    /// @notice Deterministic deployment proxy (same address on all EVM chains)
    /// @dev Deployed via keyless deployment, available on most chains
    /// @dev See: https://github.com/Arachnid/deterministic-deployment-proxy
    address public constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // ============ State ============
    address public vault;
    address public gridEx;
    address public linear;

    // ============ Main Entry Points ============

    /// @notice Main deployment function - deploys all contracts
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get chain config or use environment variables
        (address weth, address usd) = _getTokenAddresses();

        console.log("========================================");
        console.log("GridEx Protocol Deployment");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("WETH:", weth);
        console.log("USD:", usd);
        console.log("");

        // Verify CREATE2 deployer exists
        require(CREATE2_DEPLOYER.code.length > 0, "CREATE2 deployer not available on this chain");

        // Preview expected addresses
        (address expectedVault, address expectedGridEx, address expectedLinear) = computeAddresses();

        console.log("Expected Addresses:");
        console.log("  Vault:", expectedVault);
        console.log("  GridEx:", expectedGridEx);
        console.log("  Linear:", expectedLinear);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Vault (with deployer as owner)
        bytes32 vaultSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Vault"));
        bytes memory vaultBytecode = abi.encodePacked(type(Vault).creationCode, abi.encode(deployer));
        vault = _deployContract(vaultSalt, vaultBytecode, "Vault");
        require(vault == expectedVault, "Vault address mismatch!");

        // Deploy GridEx (with deployer as owner and vault address)
        bytes32 gridExSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "GridEx"));
        bytes memory gridExBytecode = abi.encodePacked(type(GridEx).creationCode, abi.encode(deployer, vault));
        gridEx = _deployContract(gridExSalt, gridExBytecode, "GridEx");
        require(gridEx == expectedGridEx, "GridEx address mismatch!");

        // Initialize GridEx with WETH and USD (chain-specific)
        if (!GridEx(payable(gridEx)).initialized()) {
            GridEx(payable(gridEx)).initialize(weth, usd);
            console.log("[OK] GridEx initialized with WETH and USD");
        } else {
            console.log("[SKIP] GridEx already initialized");
        }

        // Deploy Linear
        bytes32 linearSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Linear"));
        bytes memory linearBytecode = abi.encodePacked(type(Linear).creationCode, abi.encode(gridEx));
        linear = _deployContract(linearSalt, linearBytecode, "Linear");
        require(linear == expectedLinear, "Linear address mismatch!");

        // Configure: Whitelist Linear strategy
        if (!GridEx(payable(gridEx)).whitelistedStrategies(linear)) {
            GridEx(payable(gridEx)).setStrategyWhitelist(linear, true);
            console.log("[OK] Linear strategy whitelisted");
        } else {
            console.log("[SKIP] Linear already whitelisted");
        }

        vm.stopBroadcast();

        _printSummary(weth, usd);
    }

    /// @notice Preview deployment addresses without deploying
    function preview() public view {
        (address weth, address usd) = _getTokenAddresses();

        console.log("========================================");
        console.log("Deployment Preview");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("WETH:", weth);
        console.log("USD:", usd);
        console.log("Salt:", vm.toString(DEPLOYMENT_SALT));
        console.log("");

        (address expectedVault, address expectedGridEx, address expectedLinear) = computeAddresses();

        console.log("Expected Addresses:");
        console.log("  Vault:", expectedVault);
        console.log("  GridEx:", expectedGridEx);
        console.log("  Linear:", expectedLinear);
        console.log("");

        // Check if already deployed
        console.log("Deployment Status:");
        console.log("  Vault:", expectedVault.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
        console.log("  GridEx:", expectedGridEx.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
        console.log("  Linear:", expectedLinear.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
    }

    /// @notice Compute expected addresses for given owner
    /// @dev WETH/USD are no longer part of constructor args, so addresses are deterministic across chains
    function computeAddresses()
        public
        view
        returns (address expectedVault, address expectedGridEx, address expectedLinear)
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
    /// @dev WETH/USD are set via initialize(), so constructor only takes owner and vault
    function computeAddressesWithOwner(address _owner)
        public
        pure
        returns (address expectedVault, address expectedGridEx, address expectedLinear)
    {
        // Vault (takes owner as constructor arg - same on all chains if same owner)
        bytes32 vaultSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Vault"));
        bytes memory vaultBytecode = abi.encodePacked(type(Vault).creationCode, abi.encode(_owner));
        expectedVault = _computeAddress(vaultSalt, vaultBytecode);

        // GridEx (takes owner and vault - same on all chains if same owner)
        bytes32 gridExSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "GridEx"));
        bytes memory gridExBytecode = abi.encodePacked(type(GridEx).creationCode, abi.encode(_owner, expectedVault));
        expectedGridEx = _computeAddress(gridExSalt, gridExBytecode);

        // Linear (depends on gridEx)
        bytes32 linearSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Linear"));
        bytes memory linearBytecode = abi.encodePacked(type(Linear).creationCode, abi.encode(expectedGridEx));
        expectedLinear = _computeAddress(linearSalt, linearBytecode);
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
        console.log("  GridEx:", gridEx);
        console.log("  Linear:", linear);
        console.log("");
        console.log("Configuration:");
        console.log("  WETH:", weth);
        console.log("  USD:", usd);
        console.log("  Owner:", GridEx(payable(gridEx)).owner());
        console.log("");
        console.log("Verification Commands:");
        console.log("----------------------------------------");
        _printVerifyCommands(weth, usd);
    }

    /// @notice Print verification commands
    function _printVerifyCommands(address, address) internal view {
        address _owner = GridEx(payable(gridEx)).owner();
        string memory chainId = vm.toString(block.chainid);

        console.log("# Verify Vault");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(vault),
                " src/Vault.sol:Vault --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $(cast abi-encode 'constructor(address)' ",
                vm.toString(_owner),
                ")"
            )
        );
        console.log("");

        console.log("# Verify GridEx");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(gridEx),
                " src/GridEx.sol:GridEx --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $(cast abi-encode 'constructor(address,address)' ",
                vm.toString(_owner),
                " ",
                vm.toString(vault),
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
                vm.toString(gridEx),
                ")"
            )
        );
    }
}
