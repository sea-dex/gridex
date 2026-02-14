// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";

import {GridEx} from "../src/GridEx.sol";
import {Vault} from "../src/Vault.sol";
import {Linear} from "../src/strategy/Linear.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {ProtocolConstants} from "../src/libraries/ProtocolConstants.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
/// GridEx uses UUPS proxy pattern:
/// - Implementation: No constructor args, same address everywhere
/// - Proxy: Constructor args include (impl, initData), where initData contains
///   only (owner, vault). Chain-specific config (WETH, quote tokens) is set via
///   setWETH() and setQuoteToken() after deployment, so the proxy address is
///   identical across all chains.
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
    address public gridExImpl;
    address public gridEx; // proxy address
    address public linear;

    // ============ Main Entry Points ============

    /// @notice Main deployment function - deploys all contracts
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get chain config or use environment variables
        (address weth, address usd) = _getTokenAddresses();

        console.log("========================================");
        console.log("GridEx Protocol Deployment (UUPS Proxy)");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("WETH:", weth);
        console.log("USD:", usd);
        console.log("");

        // Verify CREATE2 deployer exists
        require(CREATE2_DEPLOYER.code.length > 0, "CREATE2 deployer not available on this chain");

        // Preview expected addresses (same on all chains)
        (address expectedVault, address expectedImpl, address expectedProxy, address expectedLinear) =
            computeAddressesWithOwner(deployer);

        console.log("Expected Addresses:");
        console.log("  Vault:", expectedVault);
        console.log("  GridEx Impl:", expectedImpl);
        console.log("  GridEx Proxy:", expectedProxy);
        console.log("  Linear:", expectedLinear);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Vault (with deployer as owner)
        bytes32 vaultSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Vault"));
        bytes memory vaultBytecode = abi.encodePacked(type(Vault).creationCode, abi.encode(deployer));
        vault = _deployContract(vaultSalt, vaultBytecode, "Vault");
        require(vault == expectedVault, "Vault address mismatch!");

        // Deploy GridEx implementation (no constructor args - _disableInitializers in constructor)
        bytes32 implSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "GridExImpl"));
        bytes memory implBytecode = type(GridEx).creationCode;
        gridExImpl = _deployContract(implSalt, implBytecode, "GridEx Implementation");
        require(gridExImpl == expectedImpl, "GridEx impl address mismatch!");

        // Deploy ERC1967Proxy pointing to GridEx implementation
        // The proxy constructor calls initialize() atomically (chain-agnostic)
        bytes memory initData = abi.encodeCall(GridEx.initialize, (deployer, vault));
        bytes32 proxySalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "GridExProxy"));
        bytes memory proxyBytecode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(gridExImpl, initData));
        gridEx = _deployContract(proxySalt, proxyBytecode, "GridEx Proxy");
        require(gridEx == expectedProxy, "GridEx proxy address mismatch!");

        console.log("[OK] GridEx initialized via proxy constructor");

        // Configure chain-specific WETH and quote tokens
        GridEx(payable(gridEx)).setWETH(weth);
        GridEx(payable(gridEx)).setQuoteToken(Currency.wrap(usd), ProtocolConstants.QUOTE_PRIORITY_USD);
        GridEx(payable(gridEx)).setQuoteToken(Currency.wrap(weth), ProtocolConstants.QUOTE_PRIORITY_WETH);
        console.log("[OK] WETH and quote tokens configured");

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
        console.log("Deployment Preview (UUPS Proxy)");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("WETH:", weth);
        console.log("USD:", usd);
        console.log("Salt:", vm.toString(DEPLOYMENT_SALT));
        console.log("");

        (address expectedVault, address expectedImpl, address expectedProxy, address expectedLinear) =
            computeAddresses(weth, usd);

        console.log("Expected Addresses:");
        console.log("  Vault:", expectedVault);
        console.log("  GridEx Impl:", expectedImpl);
        console.log("  GridEx Proxy:", expectedProxy);
        console.log("  Linear:", expectedLinear);
        console.log("");

        // Check if already deployed
        console.log("Deployment Status:");
        console.log("  Vault:", expectedVault.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
        console.log("  GridEx Impl:", expectedImpl.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
        console.log("  GridEx Proxy:", expectedProxy.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
        console.log("  Linear:", expectedLinear.code.length > 0 ? "DEPLOYED" : "NOT DEPLOYED");
    }

    /// @notice Compute expected addresses for current deployer
    /// @param weth WETH address (only used for logging, not for address computation)
    /// @param usd USD address (only used for logging, not for address computation)
    function computeAddresses(address weth, address usd)
        public
        view
        returns (address expectedVault, address expectedImpl, address expectedProxy, address expectedLinear)
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
    /// @dev With UUPS proxy, initData only encodes (owner, vault) — no chain-specific args.
    ///      Proxy address is now the same across all chains.
    function computeAddressesWithOwner(address _owner)
        public
        pure
        returns (address expectedVault, address expectedImpl, address expectedProxy, address expectedLinear)
    {
        // Vault (takes owner as constructor arg - same on all chains if same owner)
        bytes32 vaultSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Vault"));
        bytes memory vaultBytecode = abi.encodePacked(type(Vault).creationCode, abi.encode(_owner));
        expectedVault = _computeAddress(vaultSalt, vaultBytecode);

        // GridEx implementation (no constructor args - same address everywhere)
        bytes32 implSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "GridExImpl"));
        bytes memory implBytecode = type(GridEx).creationCode;
        expectedImpl = _computeAddress(implSalt, implBytecode);

        // GridEx proxy (depends only on impl, owner, vault — same across all chains)
        bytes memory initData = abi.encodeCall(GridEx.initialize, (_owner, expectedVault));
        bytes32 proxySalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "GridExProxy"));
        bytes memory proxyBytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(expectedImpl, initData));
        expectedProxy = _computeAddress(proxySalt, proxyBytecode);

        // Linear (depends on proxy address)
        bytes32 linearSalt = keccak256(abi.encodePacked(DEPLOYMENT_SALT, "Linear"));
        bytes memory linearBytecode = abi.encodePacked(type(Linear).creationCode, abi.encode(expectedProxy));
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
        console.log("  GridEx Impl:", gridExImpl);
        console.log("  GridEx Proxy:", gridEx);
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
        string memory chainId = vm.toString(block.chainid);

        console.log("# Verify Vault");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(vault),
                " src/Vault.sol:Vault --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $(cast abi-encode 'constructor(address)' ",
                vm.toString(GridEx(payable(gridEx)).owner()),
                ")"
            )
        );
        console.log("");

        console.log("# Verify GridEx Implementation (no constructor args)");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(gridExImpl),
                " src/GridEx.sol:GridEx --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY"
            )
        );
        console.log("");

        console.log("# Verify GridEx Proxy");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(gridEx),
                " lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --chain ",
                chainId,
                " --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $(cast abi-encode 'constructor(address,bytes)' ",
                vm.toString(gridExImpl),
                " <initData>)"
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
