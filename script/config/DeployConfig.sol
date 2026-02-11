// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

/// @title DeployConfig
/// @notice Configuration for multi-chain deployment
/// @dev Contains chain-specific addresses and deployment parameters
library DeployConfig {
    /// @notice Chain configuration struct
    struct ChainConfig {
        uint256 chainId;
        string name;
        address weth;
        address usd;
        string rpcEnvVar;
        string explorerApiKeyEnvVar;
        string explorerUrl;
    }

    // ============ Mainnet Chains ============

    /// @notice Ethereum Mainnet configuration
    function ethereum() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            chainId: 1,
            name: "Ethereum",
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            usd: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
            rpcEnvVar: "ETH_RPC",
            explorerApiKeyEnvVar: "ETHERSCAN_API_KEY",
            explorerUrl: "https://etherscan.io"
        });
    }

    /// @notice Arbitrum One configuration
    function arbitrum() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            chainId: 42161,
            name: "Arbitrum One",
            weth: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            usd: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831, // USDC
            rpcEnvVar: "ARB_RPC",
            explorerApiKeyEnvVar: "ARBISCAN_API_KEY",
            explorerUrl: "https://arbiscan.io"
        });
    }

    /// @notice Optimism configuration
    function optimism() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            chainId: 10,
            name: "Optimism",
            weth: 0x4200000000000000000000000000000000000006,
            usd: 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85, // USDC
            rpcEnvVar: "OP_RPC",
            explorerApiKeyEnvVar: "OPSCAN_API_KEY",
            explorerUrl: "https://optimistic.etherscan.io"
        });
    }

    /// @notice Base configuration
    function base() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            chainId: 8453,
            name: "Base",
            weth: 0x4200000000000000000000000000000000000006,
            usd: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // USDC
            rpcEnvVar: "BASE_RPC",
            explorerApiKeyEnvVar: "BASESCAN_API_KEY",
            explorerUrl: "https://basescan.org"
        });
    }

    /// @notice BSC configuration
    function bsc() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            chainId: 56,
            name: "BSC",
            weth: 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c, // WBNB
            usd: 0x55d398326f99059fF775485246999027B3197955, // USDT
            rpcEnvVar: "BSC_RPC",
            explorerApiKeyEnvVar: "BSCSCAN_API_KEY",
            explorerUrl: "https://bscscan.com"
        });
    }

    /// @notice Polygon configuration
    function polygon() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            chainId: 137,
            name: "Polygon",
            weth: 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270, // WMATIC
            usd: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359, // USDC
            rpcEnvVar: "POLYGON_RPC",
            explorerApiKeyEnvVar: "POLYGONSCAN_API_KEY",
            explorerUrl: "https://polygonscan.com"
        });
    }

    /// @notice Avalanche configuration
    function avalanche() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            chainId: 43114,
            name: "Avalanche",
            weth: 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7, // WAVAX
            usd: 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E, // USDC
            rpcEnvVar: "AVAX_RPC",
            explorerApiKeyEnvVar: "SNOWTRACE_API_KEY",
            explorerUrl: "https://snowtrace.io"
        });
    }

    // ============ Testnet Chains ============

    /// @notice Sepolia testnet configuration
    function sepolia() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            chainId: 11155111,
            name: "Sepolia",
            weth: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
            usd: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, // USDC
            rpcEnvVar: "SEPOLIA_RPC",
            explorerApiKeyEnvVar: "ETHERSCAN_API_KEY",
            explorerUrl: "https://sepolia.etherscan.io"
        });
    }

    /// @notice Arbitrum Sepolia testnet configuration
    function arbitrumSepolia() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            chainId: 421614,
            name: "Arbitrum Sepolia",
            weth: 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73,
            usd: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d, // USDC
            rpcEnvVar: "ARB_SEPOLIA_RPC",
            explorerApiKeyEnvVar: "ARBISCAN_API_KEY",
            explorerUrl: "https://sepolia.arbiscan.io"
        });
    }

    /// @notice Base Sepolia testnet configuration
    function baseSepolia() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            chainId: 84532,
            name: "Base Sepolia",
            weth: 0x4200000000000000000000000000000000000006,
            usd: 0x036CbD53842c5426634e7929541eC2318f3dCF7e, // USDC
            rpcEnvVar: "BASE_SEPOLIA_RPC",
            explorerApiKeyEnvVar: "BASESCAN_API_KEY",
            explorerUrl: "https://sepolia.basescan.org"
        });
    }

    /// @notice BSC Testnet configuration
    function bscTestnet() internal pure returns (ChainConfig memory) {
        return ChainConfig({
            chainId: 97,
            name: "BSC Testnet",
            weth: 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd, // WBNB
            usd: 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd, // USDT
            rpcEnvVar: "BSC_TESTNET_RPC",
            explorerApiKeyEnvVar: "BSCSCAN_API_KEY",
            explorerUrl: "https://testnet.bscscan.com"
        });
    }

    /// @notice Get configuration by chain ID
    function getConfig(uint256 chainId) internal pure returns (ChainConfig memory) {
        // Mainnets
        if (chainId == 1) return ethereum();
        if (chainId == 42161) return arbitrum();
        if (chainId == 10) return optimism();
        if (chainId == 8453) return base();
        if (chainId == 56) return bsc();
        if (chainId == 137) return polygon();
        if (chainId == 43114) return avalanche();

        // Testnets
        if (chainId == 11155111) return sepolia();
        if (chainId == 421614) return arbitrumSepolia();
        if (chainId == 84532) return baseSepolia();
        if (chainId == 97) return bscTestnet();

        revert("Unsupported chain");
    }
}
