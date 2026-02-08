# GridEx Protocol - Deployment Guide

This guide explains how to deploy GridEx contracts to multiple chains with **deterministic addresses** using CREATE2.

## Overview

The deployment system uses CREATE2 to ensure contracts are deployed to the **same address** across all EVM-compatible chains. This is achieved through:

1. **Deterministic Deployment Proxy** (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) - Available on all major chains
2. **Consistent Salt** - Same salt value used across all deployments
3. **Identical Bytecode** - Same contract bytecode including constructor arguments

## Files

| File | Description |
|------|-------------|
| `Deploy.s.sol` | Main deployment script with CREATE2 |
| `config/DeployConfig.sol` | Chain-specific configurations (WETH, USD addresses) |
| `deploy.sh` | Shell script for multi-chain deployment |
| `.env.example` | Environment variable template |
| `Create2Deployer.sol` | Custom CREATE2 deployer (optional) |
| `DeployDeterministic.s.sol` | Alternative deployment script |

## Prerequisites

1. **Foundry** installed (`forge`, `cast`)
2. **Private key** with sufficient funds on target chains
3. **RPC URLs** for target chains
4. **API keys** for block explorers (optional, for verification)

## Quick Start

### 1. Setup Environment

```bash
# Copy environment template
cp script/.env.example script/.env

# Edit with your values
vim script/.env
```

### 2. Preview Deployment

```bash
# Preview addresses without deploying
source script/.env
./script/deploy.sh preview base-sepolia
```

### 3. Deploy

```bash
# Deploy to a single chain
./script/deploy.sh deploy base-sepolia

# Deploy to multiple chains
./script/deploy.sh all base-sepolia arbitrum-sepolia sepolia
```

## Achieving Same Addresses Across Chains

### Understanding CREATE2

The CREATE2 address is computed as:
```
address = keccak256(0xff ++ deployer ++ salt ++ keccak256(bytecode))[12:]
```

For **identical addresses** across chains:
- ✅ Same CREATE2 deployer (we use `0x4e59b44847b379578588920cA78FbF26c0B4956C`)
- ✅ Same salt (defined in `Deploy.s.sol`)
- ⚠️ Same bytecode **including constructor arguments**

### The Challenge

GridEx constructor requires:
```solidity
constructor(address weth_, address usd_, address _vault)
```

Since WETH and USD addresses differ per chain, the bytecode differs, resulting in different addresses.

### Solutions

#### Option A: Use Canonical Token Addresses (Recommended for Production)

Deploy your own WETH and USD tokens using CREATE2 first, ensuring they have the same address on all chains:

```bash
# 1. Deploy canonical WETH/USD to all chains first
# 2. Use those addresses for GridEx deployment
WETH_ADDRESS=0x... USD_ADDRESS=0x... ./script/deploy.sh deploy base
```

#### Option B: Accept Different Addresses Per Chain

If using native WETH/USD on each chain, accept that GridEx will have different addresses:

```bash
# Uses chain-specific WETH/USD from DeployConfig.sol
./script/deploy.sh deploy base
```

#### Option C: Use Proxy Pattern

Deploy a minimal proxy with no constructor args, then initialize:

```solidity
// Proxy has no constructor args = same address everywhere
contract GridExProxy {
    function initialize(address weth, address usd, address vault) external;
}
```

## Deployment Commands

### Using Shell Script

```bash
# Preview deployment
./script/deploy.sh preview <chain>

# Deploy to single chain
./script/deploy.sh deploy <chain>

# Deploy to multiple chains
./script/deploy.sh all <chain1> <chain2> ...

# Verify contracts
./script/deploy.sh verify <chain> <contract> <address> [args...]
```

### Using Forge Directly

```bash
# Preview
forge script script/Deploy.s.sol --sig "preview()" --rpc-url $RPC_URL

# Deploy
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify

# With custom tokens
WETH_ADDRESS=0x... USD_ADDRESS=0x... forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

## Supported Chains

### Mainnets

| Chain | Chain ID | RPC Env Var |
|-------|----------|-------------|
| Ethereum | 1 | `ETH_RPC` |
| Arbitrum | 42161 | `ARB_RPC` |
| Optimism | 10 | `OP_RPC` |
| Base | 8453 | `BASE_RPC` |
| BSC | 56 | `BSC_RPC` |
| Polygon | 137 | `POLYGON_RPC` |
| Avalanche | 43114 | `AVAX_RPC` |

### Testnets

| Chain | Chain ID | RPC Env Var |
|-------|----------|-------------|
| Sepolia | 11155111 | `SEPOLIA_RPC` |
| Arbitrum Sepolia | 421614 | `ARB_SEPOLIA_RPC` |
| Base Sepolia | 84532 | `BASE_SEPOLIA_RPC` |
| BSC Testnet | 97 | `BSC_TESTNET_RPC` |

## Contract Verification

Contracts are automatically verified if you provide explorer API keys. Manual verification:

```bash
# Vault (no constructor args)
forge verify-contract \
  --chain-id 84532 \
  --etherscan-api-key $BASESCAN_API_KEY \
  0x... \
  src/Vault.sol:Vault

# GridEx
forge verify-contract \
  --chain-id 84532 \
  --etherscan-api-key $BASESCAN_API_KEY \
  0x... \
  src/GridEx.sol:GridEx \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" $WETH $USD $VAULT)

# Linear
forge verify-contract \
  --chain-id 84532 \
  --etherscan-api-key $BASESCAN_API_KEY \
  0x... \
  src/strategy/Linear.sol:Linear \
  --constructor-args $(cast abi-encode "constructor(address)" $GRIDEX)
```

## Post-Deployment Checklist

- [ ] Verify all contracts on block explorers
- [ ] Confirm Linear strategy is whitelisted
- [ ] Transfer ownership if needed
- [ ] Test basic functionality (place order, fill order)
- [ ] Update frontend/backend with new addresses
- [ ] Document deployed addresses

## Troubleshooting

### "CREATE2 deployer not available"

The deterministic deployment proxy isn't deployed on this chain. You can:
1. Deploy it yourself using the keyless deployment method
2. Use a different CREATE2 factory

### "Address mismatch"

The computed address doesn't match the expected address. Check:
1. Salt is correct
2. Constructor arguments are identical
3. Contract bytecode hasn't changed

### "Deployment failed"

Common causes:
1. Insufficient gas
2. Contract already deployed at address
3. Constructor reverted

## Security Considerations

1. **Private Key Security**: Never commit `.env` files
2. **Verify Bytecode**: Ensure deployed bytecode matches source
3. **Ownership**: Transfer ownership to multisig after deployment
4. **Testing**: Test on testnets before mainnet deployment

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    CREATE2 Deployer                          │
│            0x4e59b44847b379578588920cA78FbF26c0B4956C        │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ CREATE2
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         Vault                                │
│                   (Same address all chains)                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ constructor arg
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        GridEx                                │
│    (Same address if WETH/USD are same, else different)      │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ constructor arg
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        Linear                                │
│              (Depends on GridEx address)                     │
└─────────────────────────────────────────────────────────────┘
```

## Example: Full Multi-Chain Deployment

```bash
# 1. Setup
source script/.env

# 2. Preview on all chains
for chain in base-sepolia arbitrum-sepolia sepolia; do
  echo "=== $chain ==="
  ./script/deploy.sh preview $chain
done

# 3. Deploy to testnets
./script/deploy.sh all base-sepolia arbitrum-sepolia sepolia

# 4. Verify deployment
for chain in base-sepolia arbitrum-sepolia sepolia; do
  echo "=== Checking $chain ==="
  ./script/deploy.sh preview $chain
done

# 5. Deploy to mainnets (after testing)
./script/deploy.sh all base arbitrum optimism
```
