#!/bin/bash

# ============================================================
# GridEx Protocol - Multi-Chain Deployment Script
# ============================================================
# 
# This script deploys GridEx contracts to multiple chains using
# CREATE2 for deterministic addresses.
#
# Prerequisites:
# 1. Set PRIVATE_KEY environment variable
# 2. Set RPC URLs for each chain (see below)
# 3. Set API keys for contract verification (optional)
#
# Usage:
#   ./script/deploy.sh [command] [chain]
#
# Commands:
#   preview  - Preview deployment addresses without deploying
#   deploy   - Deploy contracts to specified chain
#   verify   - Verify contracts on block explorer
#   all      - Deploy to all configured chains
#
# Examples:
#   ./script/deploy.sh preview base
#   ./script/deploy.sh deploy arbitrum
#   ./script/deploy.sh all
#
# ============================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# Configuration
# ============================================================

# Deployment salt - MUST be the same across all chains
DEPLOYMENT_SALT="GridEx.V1.2024.Production"

# Script path
DEPLOY_SCRIPT="script/Deploy.s.sol"

# ============================================================
# Chain Configurations (bash 3.x compatible)
# ============================================================

# Get chain ID for a given chain name
get_chain_id() {
    local chain=$1
    case "$chain" in
        # Mainnet chains
        "ethereum")        echo "1" ;;
        "arbitrum")        echo "42161" ;;
        "optimism")        echo "10" ;;
        "base")            echo "8453" ;;
        "bsc")             echo "56" ;;
        "polygon")         echo "137" ;;
        "avalanche")       echo "43114" ;;
        # Testnet chains
        "sepolia")         echo "11155111" ;;
        "arbitrum-sepolia") echo "421614" ;;
        "base-sepolia")    echo "84532" ;;
        "bsc-testnet")     echo "97" ;;
        *)                 echo "" ;;
    esac
}

# Get RPC URL environment variable name for a given chain
get_rpc_var_name() {
    local chain=$1
    case "$chain" in
        "ethereum")        echo "ETH_RPC" ;;
        "arbitrum")        echo "ARB_RPC" ;;
        "optimism")        echo "OP_RPC" ;;
        "base")            echo "BASE_RPC" ;;
        "bsc")             echo "BSC_RPC" ;;
        "polygon")         echo "POLYGON_RPC" ;;
        "avalanche")       echo "AVAX_RPC" ;;
        "sepolia")         echo "SEPOLIA_RPC" ;;
        "arbitrum-sepolia") echo "ARB_SEPOLIA_RPC" ;;
        "base-sepolia")    echo "BASE_SEPOLIA_RPC" ;;
        "bsc-testnet")     echo "BSC_TESTNET_RPC" ;;
        *)                 echo "" ;;
    esac
}

# Get explorer API key environment variable name for a given chain
get_explorer_var_name() {
    local chain=$1
    case "$chain" in
        "ethereum")        echo "ETHERSCAN_API_KEY" ;;
        "arbitrum")        echo "ARBISCAN_API_KEY" ;;
        "optimism")        echo "OPSCAN_API_KEY" ;;
        "base")            echo "BASESCAN_API_KEY" ;;
        "bsc")             echo "BSCSCAN_API_KEY" ;;
        "polygon")         echo "POLYGONSCAN_API_KEY" ;;
        "avalanche")       echo "SNOWTRACE_API_KEY" ;;
        "sepolia")         echo "ETHERSCAN_API_KEY" ;;
        "arbitrum-sepolia") echo "ARBISCAN_API_KEY" ;;
        "base-sepolia")    echo "BASESCAN_API_KEY" ;;
        "bsc-testnet")     echo "BSCSCAN_API_KEY" ;;
        *)                 echo "" ;;
    esac
}

# List of all available chains
ALL_CHAINS="ethereum arbitrum optimism base bsc polygon avalanche sepolia arbitrum-sepolia base-sepolia bsc-testnet"

# ============================================================
# Helper Functions
# ============================================================

print_header() {
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_prerequisites() {
    if [ -z "$PRIVATE_KEY" ]; then
        print_error "PRIVATE_KEY environment variable is not set"
        exit 1
    fi
    
    if ! command -v forge &> /dev/null; then
        print_error "Foundry (forge) is not installed"
        exit 1
    fi
    
    if ! command -v cast &> /dev/null; then
        print_error "Foundry (cast) is not installed"
        exit 1
    fi
}

get_rpc_url() {
    local chain=$1
    local rpc_var=$(get_rpc_var_name "$chain")
    
    if [ -z "$rpc_var" ]; then
        print_error "Unknown chain: $chain"
        return 1
    fi
    
    local rpc_url=$(eval echo "\$$rpc_var")
    
    if [ -z "$rpc_url" ]; then
        print_error "RPC URL not set for $chain (set $rpc_var)"
        return 1
    fi
    
    echo "$rpc_url"
}

get_explorer_key() {
    local chain=$1
    local key_var=$(get_explorer_var_name "$chain")
    
    if [ -z "$key_var" ]; then
        echo ""
        return
    fi
    
    local api_key=$(eval echo "\$$key_var")
    echo "$api_key"
}

# ============================================================
# Commands
# ============================================================

cmd_preview() {
    local chain=$1
    
    if [ -z "$chain" ]; then
        print_error "Please specify a chain"
        echo "Available chains: $ALL_CHAINS"
        exit 1
    fi
    
    local rpc_url=$(get_rpc_url "$chain")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    print_header "Preview Deployment - $chain"
    
    forge script "$DEPLOY_SCRIPT" \
        --sig "preview()" \
        --rpc-url "$rpc_url" \
        -vvv
}

cmd_deploy() {
    local chain=$1
    local verify_flag=""
    
    if [ -z "$chain" ]; then
        print_error "Please specify a chain"
        echo "Available chains: $ALL_CHAINS"
        exit 1
    fi
    
    local rpc_url=$(get_rpc_url "$chain")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    local explorer_key=$(get_explorer_key "$chain")
    if [ -n "$explorer_key" ]; then
        verify_flag="--verify --etherscan-api-key $explorer_key"
        print_info "Contract verification enabled"
    else
        print_warning "No explorer API key found, skipping verification"
    fi
    
    print_header "Deploying to $chain"
    
    forge script "$DEPLOY_SCRIPT" \
        --rpc-url "$rpc_url" \
        --broadcast \
        $verify_flag \
        -vvvv
    
    if [ $? -eq 0 ]; then
        print_success "Deployment to $chain completed!"
    else
        print_error "Deployment to $chain failed!"
        exit 1
    fi
}

cmd_deploy_all() {
    local chains=("$@")
    
    if [ ${#chains[@]} -eq 0 ]; then
        # Default to all testnet chains
        chains=("base-sepolia" "arbitrum-sepolia" "sepolia")
    fi
    
    print_header "Multi-Chain Deployment"
    echo "Chains: ${chains[*]}"
    echo ""
    
    local failed_chains=()
    local success_chains=()
    
    for chain in "${chains[@]}"; do
        echo ""
        print_info "Deploying to $chain..."
        
        if cmd_deploy "$chain"; then
            success_chains+=("$chain")
        else
            failed_chains+=("$chain")
        fi
    done
    
    echo ""
    print_header "Deployment Summary"
    
    if [ ${#success_chains[@]} -gt 0 ]; then
        print_success "Successful: ${success_chains[*]}"
    fi
    
    if [ ${#failed_chains[@]} -gt 0 ]; then
        print_error "Failed: ${failed_chains[*]}"
        exit 1
    fi
}

cmd_verify() {
    local chain=$1
    local contract=$2
    local address=$3
    
    if [ -z "$chain" ] || [ -z "$contract" ] || [ -z "$address" ]; then
        print_error "Usage: $0 verify <chain> <contract> <address>"
        echo "Contracts: Vault, GridEx, Linear"
        exit 1
    fi
    
    local rpc_url=$(get_rpc_url "$chain")
    local explorer_key=$(get_explorer_key "$chain")
    local chain_id=$(get_chain_id "$chain")
    
    if [ -z "$explorer_key" ]; then
        print_error "No explorer API key found for $chain"
        exit 1
    fi
    
    print_header "Verifying $contract on $chain"
    
    case $contract in
        "Vault")
            forge verify-contract \
                --chain-id "$chain_id" \
                --etherscan-api-key "$explorer_key" \
                "$address" \
                src/Vault.sol:Vault
            ;;
        "GridEx")
            if [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ]; then
                print_error "GridEx requires: <weth> <usd> <vault>"
                exit 1
            fi
            forge verify-contract \
                --chain-id "$chain_id" \
                --etherscan-api-key "$explorer_key" \
                "$address" \
                src/GridEx.sol:GridEx \
                --constructor-args $(cast abi-encode "constructor(address,address,address)" "$4" "$5" "$6")
            ;;
        "Linear")
            if [ -z "$4" ]; then
                print_error "Linear requires: <gridex>"
                exit 1
            fi
            forge verify-contract \
                --chain-id "$chain_id" \
                --etherscan-api-key "$explorer_key" \
                "$address" \
                src/strategy/Linear.sol:Linear \
                --constructor-args $(cast abi-encode "constructor(address)" "$4")
            ;;
        *)
            print_error "Unknown contract: $contract"
            exit 1
            ;;
    esac
}

cmd_help() {
    echo "GridEx Protocol - Multi-Chain Deployment Script"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  preview <chain>     Preview deployment addresses"
    echo "  deploy <chain>      Deploy to a specific chain"
    echo "  all [chains...]     Deploy to multiple chains"
    echo "  verify <chain> <contract> <address> [args...]"
    echo "                      Verify a contract on block explorer"
    echo "  help                Show this help message"
    echo ""
    echo "Available chains:"
    echo "  Mainnets: ethereum, arbitrum, optimism, base, bsc, polygon, avalanche"
    echo "  Testnets: sepolia, arbitrum-sepolia, base-sepolia, bsc-testnet"
    echo ""
    echo "Environment variables:"
    echo "  PRIVATE_KEY         Deployer private key (required)"
    echo "  ETH_RPC             Ethereum RPC URL"
    echo "  ARB_RPC             Arbitrum RPC URL"
    echo "  OP_RPC              Optimism RPC URL"
    echo "  BASE_RPC            Base RPC URL"
    echo "  BSC_RPC             BSC RPC URL"
    echo "  POLYGON_RPC         Polygon RPC URL"
    echo "  AVAX_RPC            Avalanche RPC URL"
    echo "  SEPOLIA_RPC         Sepolia RPC URL"
    echo "  ARB_SEPOLIA_RPC     Arbitrum Sepolia RPC URL"
    echo "  BASE_SEPOLIA_RPC    Base Sepolia RPC URL"
    echo "  BSC_TESTNET_RPC     BSC Testnet RPC URL"
    echo ""
    echo "  ETHERSCAN_API_KEY   Etherscan API key"
    echo "  ARBISCAN_API_KEY    Arbiscan API key"
    echo "  BASESCAN_API_KEY    Basescan API key"
    echo "  BSCSCAN_API_KEY     BSCscan API key"
    echo "  POLYGONSCAN_API_KEY Polygonscan API key"
    echo "  SNOWTRACE_API_KEY   Snowtrace API key"
    echo ""
    echo "Examples:"
    echo "  $0 preview base-sepolia"
    echo "  $0 deploy arbitrum"
    echo "  $0 all base-sepolia arbitrum-sepolia"
    echo "  $0 verify base-sepolia Vault 0x..."
}

# ============================================================
# Main
# ============================================================

# Load .env file if it exists
load_env() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local env_file="$script_dir/.env"
    
    if [ -f "$env_file" ]; then
        # Export variables from .env file, ignoring comments and empty lines
        set -a
        source "$env_file"
        set +a
        print_info "Loaded environment from $env_file"
    fi
}

main() {
    load_env
    check_prerequisites
    
    local command=$1
    shift || true
    
    case $command in
        "preview")
            cmd_preview "$@"
            ;;
        "deploy")
            cmd_deploy "$@"
            ;;
        "all")
            cmd_deploy_all "$@"
            ;;
        "verify")
            cmd_verify "$@"
            ;;
        "help"|"--help"|"-h"|"")
            cmd_help
            ;;
        *)
            print_error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
