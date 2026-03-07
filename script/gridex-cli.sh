#!/bin/bash
# GridEx Router Facet Call Helper
# This script provides convenient functions to call GridEx Router functions through fallback.
# When Router/Vault ownership has been transferred to TimelockController, admin calls will
# schedule or execute through timelock instead of sending directly to the target contract.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values - override in .env or pass as arguments
: ${RPC_URL:=""}
: ${PRIVATE_KEY:=""}
: ${ROUTER_ADDRESS:=""}
: ${TIMELOCK_ADDRESS:=""}
: ${TIMELOCK_ACTION:="schedule"}
: ${TIMELOCK_DELAY:=""}
: ${TIMELOCK_PREDECESSOR:="0x0000000000000000000000000000000000000000000000000000000000000000"}
: ${TIMELOCK_SALT:="0x0000000000000000000000000000000000000000000000000000000000000000"}

# Load .env if exists
# if [ -f ".env" ]; then
#     source .env
# fi
# Load .env file if it exists
load_env() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local env_file="$script_dir/.env"
    
    if [ -f "$env_file" ]; then
        # Export variables from .env file, ignoring comments and empty lines
        set -a
        source "$env_file"
        set +a
        echo -e "${YELLOW}Loaded environment from $env_file${NC}"
    fi
}

load_env

# Helper function to print usage
print_error() {
    echo -e "${RED}Error: $1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

# Check required variables
check_config() {
    if [ -z "$RPC_URL" ]; then
        print_error "RPC_URL not set. Set it in .env or export it."
        exit 1
    fi
    if [ -z "$ROUTER_ADDRESS" ]; then
        print_error "ROUTER_ADDRESS not set. Set it in .env or export it."
        exit 1
    fi
}

# Check if private key is set for write operations
check_private_key() {
    if [ -z "$PRIVATE_KEY" ]; then
        print_error "PRIVATE_KEY not set. Set it in .env or export it."
        exit 1
    fi
}

# Get vault address from router
get_vault_address() {
    check_config
    cast call "$ROUTER_ADDRESS" "vault()(address)" --rpc-url "$RPC_URL" 2>/dev/null | tr -d '[:space:]'
}

# Get router owner address
get_router_owner_address() {
    check_config
    cast call "$ROUTER_ADDRESS" "owner()(address)" --rpc-url "$RPC_URL" 2>/dev/null | tr -d '[:space:]'
}

# Get router guardian address
get_router_guardian_address() {
    check_config
    cast call "$ROUTER_ADDRESS" "guardian()(address)" --rpc-url "$RPC_URL" 2>/dev/null | tr -d '[:space:]'
}

# Get owner address of a contract implementing owner()
get_contract_owner_address() {
    local contract_address="$1"
    cast call "$contract_address" "owner()(address)" --rpc-url "$RPC_URL" 2>/dev/null | tr -d '[:space:]'
}

# Get signer address from private key
get_signer_address() {
    cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null | tr -d '[:space:]'
}

# Normalize address to lowercase for comparisons
normalize_address() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

is_contract_address() {
    local address="$1"
    local code
    code="$(cast code "$address" --rpc-url "$RPC_URL" 2>/dev/null | tr -d '[:space:]')"
    [ -n "$code" ] && [ "$code" != "0x" ]
}

get_timelock_address() {
    if [ -n "$TIMELOCK_ADDRESS" ]; then
        echo "$TIMELOCK_ADDRESS"
        return
    fi

    get_router_owner_address
}

require_timelock_controller() {
    local timelock_address="$1"
    if ! cast call "$timelock_address" "getMinDelay()(uint256)" --rpc-url "$RPC_URL" >/dev/null 2>&1; then
        print_error "Resolved owner $timelock_address does not look like a TimelockController. Set TIMELOCK_ADDRESS explicitly or use the direct owner signer."
        exit 1
    fi
}

get_timelock_delay() {
    local timelock_address="$1"
    if [ -n "$TIMELOCK_DELAY" ]; then
        echo "$TIMELOCK_DELAY"
        return
    fi

    cast call "$timelock_address" "getMinDelay()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null | tr -d '[:space:]'
}

send_via_timelock() {
    local target="$1"
    local signature="$2"
    shift 2
    local args=("$@")
    local timelock_address
    local calldata
    local action
    local delay

    timelock_address="$(get_timelock_address)"
    if [ -z "$timelock_address" ]; then
        print_error "Unable to resolve timelock address"
        exit 1
    fi
    require_timelock_controller "$timelock_address"

    calldata="$(cast calldata "$signature" "${args[@]}")"
    action="$(echo "$TIMELOCK_ACTION" | tr '[:upper:]' '[:lower:]')"

    if [ "$action" = "schedule" ]; then
        delay="$(get_timelock_delay "$timelock_address")"
        if [ -z "$delay" ]; then
            print_error "Unable to resolve timelock delay"
            exit 1
        fi

        print_info "Scheduling timelock operation via $timelock_address..."
        cast send "$timelock_address" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
            "$target" "0" "$calldata" "$TIMELOCK_PREDECESSOR" "$TIMELOCK_SALT" "$delay" \
            --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
        print_success "Timelock operation scheduled"
        print_info "Re-run the same command with TIMELOCK_ACTION=execute after the delay has elapsed."
        return
    fi

    if [ "$action" = "execute" ]; then
        print_info "Executing timelock operation via $timelock_address..."
        cast send "$timelock_address" "execute(address,uint256,bytes,bytes32,bytes32)" \
            "$target" "0" "$calldata" "$TIMELOCK_PREDECESSOR" "$TIMELOCK_SALT" \
            --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
        print_success "Timelock operation executed"
        return
    fi

    print_error "Invalid TIMELOCK_ACTION: $TIMELOCK_ACTION (expected schedule or execute)"
    exit 1
}

send_admin_call() {
    local target="$1"
    local signature="$2"
    shift 2
    local args=("$@")
    local signer
    local owner

    signer="$(get_signer_address)"
    owner="$(get_contract_owner_address "$target")"

    if [ -z "$signer" ] || [ -z "$owner" ]; then
        print_error "Unable to resolve signer or target owner"
        exit 1
    fi

    if [ "$(normalize_address "$signer")" = "$(normalize_address "$owner")" ]; then
        cast send "$target" "$signature" "${args[@]}" \
            --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
        return
    fi

    if ! is_contract_address "$owner"; then
        print_error "Signer is not current owner of $target (owner: $owner, signer: $signer)"
        exit 1
    fi

    if [ "$(normalize_address "$owner")" != "$(normalize_address "$(get_timelock_address)")" ]; then
        print_error "Target owner $owner does not match resolved timelock $(get_timelock_address)"
        exit 1
    fi

    send_via_timelock "$target" "$signature" "${args[@]}"
}

# ═══════════════════════════════════════════════════════════════════
#  ADMIN FACET FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

# Set WETH address
admin_set_weth() {
    local weth_address="$1"
    if [ -z "$weth_address" ]; then
        print_error "Usage: $0 admin_set_weth <WETH_ADDRESS>"
        exit 1
    fi
    check_config
    check_private_key
    
    print_info "Setting WETH to $weth_address..."
    send_admin_call "$ROUTER_ADDRESS" "setWETH(address)" "$weth_address"
    print_success "WETH admin request submitted"
}

# Set quote token priority
admin_set_quote_token() {
    local token_address="$1"
    local priority="$2"
    if [ -z "$token_address" ] || [ -z "$priority" ]; then
        print_error "Usage: $0 admin_set_quote_token <TOKEN_ADDRESS> <PRIORITY>"
        exit 1
    fi
    check_config
    check_private_key
    
    print_info "Setting quote token $token_address with priority $priority..."
    send_admin_call "$ROUTER_ADDRESS" "setQuoteToken(address,uint256)" "$token_address" "$priority"
    print_success "Quote token admin request submitted"
}

# Set strategy whitelist
admin_set_strategy_whitelist() {
    local strategy_address="$1"
    local whitelisted="$2"
    if [ -z "$strategy_address" ] || [ -z "$whitelisted" ]; then
        print_error "Usage: $0 admin_set_strategy_whitelist <STRATEGY_ADDRESS> <true|false>"
        exit 1
    fi
    check_config
    check_private_key
    
    local bool_value
    if [ "$whitelisted" = "true" ]; then
        bool_value="true"
    else
        bool_value="false"
    fi
    
    print_info "Setting strategy $strategy_address whitelist to $whitelisted..."
    send_admin_call "$ROUTER_ADDRESS" "setStrategyWhitelist(address,bool)" "$strategy_address" "$bool_value"
    print_success "Strategy whitelist admin request submitted"
}

# Set oneshot protocol fee
admin_set_oneshot_fee() {
    local fee_bps="$1"
    if [ -z "$fee_bps" ]; then
        print_error "Usage: $0 admin_set_oneshot_fee <FEE_BPS>"
        exit 1
    fi
    check_config
    check_private_key
    
    print_info "Setting oneshot protocol fee to $fee_bps bps..."
    send_admin_call "$ROUTER_ADDRESS" "setOneshotProtocolFeeBps(uint32)" "$fee_bps"
    print_success "Protocol fee admin request submitted"
}

# Pause trading
admin_pause() {
    check_config
    check_private_key
    local signer
    local owner
    local guardian

    signer="$(get_signer_address)"
    owner="$(get_router_owner_address)"
    guardian="$(get_router_guardian_address)"

    print_info "Pausing trading..."
    if [ "$(normalize_address "$signer")" = "$(normalize_address "$guardian")" ] || \
        [ "$(normalize_address "$signer")" = "$(normalize_address "$owner")" ]; then
        cast send "$ROUTER_ADDRESS" "pause()" \
            --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    else
        send_admin_call "$ROUTER_ADDRESS" "pause()"
    fi
    print_success "Pause request submitted"
}

# Unpause trading
admin_unpause() {
    check_config
    check_private_key
    
    print_info "Unpausing trading..."
    send_admin_call "$ROUTER_ADDRESS" "unpause()"
    print_success "Unpause request submitted"
}

# Rescue ETH
admin_rescue_eth() {
    local to_address="$1"
    local amount="$2"
    if [ -z "$to_address" ] || [ -z "$amount" ]; then
        print_error "Usage: $0 admin_rescue_eth <TO_ADDRESS> <AMOUNT_IN_WEI>"
        exit 1
    fi
    check_config
    check_private_key
    
    print_info "Rescuing $amount wei ETH to $to_address..."
    send_admin_call "$ROUTER_ADDRESS" "rescueEth(address,uint256)" "$to_address" "$amount"
    print_success "ETH rescue request submitted"
}

# Transfer ownership
admin_transfer_ownership() {
    local new_owner="$1"
    local target="${2:-both}" # both | router | vault
    local zero_address="0x0000000000000000000000000000000000000000"
    if [ -z "$new_owner" ]; then
        print_error "Usage: $0 admin_transfer_ownership <NEW_OWNER_ADDRESS> [both|router|vault]"
        exit 1
    fi
    if [ "$(normalize_address "$new_owner")" = "$zero_address" ]; then
        print_error "NEW_OWNER_ADDRESS cannot be zero address"
        exit 1
    fi
    if [ "$target" != "both" ] && [ "$target" != "router" ] && [ "$target" != "vault" ]; then
        print_error "Invalid target: $target (expected: both|router|vault)"
        exit 1
    fi
    check_config
    check_private_key

    local signer
    local vault_address=""
    local router_owner=""
    local vault_owner=""
    local timelock_address=""

    signer="$(get_signer_address)"
    if [ -z "$signer" ] || [ "$(normalize_address "$signer")" = "$zero_address" ]; then
        print_error "Failed to derive signer address from PRIVATE_KEY"
        exit 1
    fi

    if [ "$target" = "both" ] || [ "$target" = "vault" ]; then
        vault_address="$(get_vault_address)"
        if [ -z "$vault_address" ] || [ "$vault_address" = "$zero_address" ]; then
            print_error "Failed to resolve vault address from router"
            exit 1
        fi
    fi

    if [ "$target" = "both" ] || [ "$target" = "router" ]; then
        router_owner="$(get_router_owner_address)"
        timelock_address="$(get_timelock_address)"
        if [ "$(normalize_address "$router_owner")" != "$(normalize_address "$signer")" ] && \
            [ "$(normalize_address "$router_owner")" != "$(normalize_address "$timelock_address")" ]; then
            print_error "Signer is not current Router owner (router owner: $router_owner, signer: $signer)"
            exit 1
        fi
    fi

    if [ "$target" = "both" ] || [ "$target" = "vault" ]; then
        vault_owner="$(get_contract_owner_address "$vault_address")"
        timelock_address="$(get_timelock_address)"
        if [ "$(normalize_address "$vault_owner")" != "$(normalize_address "$signer")" ] && \
            [ "$(normalize_address "$vault_owner")" != "$(normalize_address "$timelock_address")" ]; then
            print_error "Signer is not current Vault owner (vault owner: $vault_owner, signer: $signer)"
            exit 1
        fi
    fi

    if [ "$target" = "both" ] || [ "$target" = "router" ]; then
        print_info "Transferring Router ownership to $new_owner..."
        send_admin_call "$ROUTER_ADDRESS" "transferOwnership(address)" "$new_owner"
        print_success "Router ownership transfer request submitted"
    fi

    if [ "$target" = "both" ] || [ "$target" = "vault" ]; then
        print_info "Transferring Vault ownership to $new_owner..."
        send_admin_call "$vault_address" "transferOwnership(address)" "$new_owner"
        print_success "Vault ownership transfer request submitted"
    fi
}

# Set single facet
admin_set_facet() {
    local selector="$1"
    local facet_address="$2"
    if [ -z "$selector" ] || [ -z "$facet_address" ]; then
        print_error "Usage: $0 admin_set_facet <SELECTOR_4BYTES> <FACET_ADDRESS>"
        exit 1
    fi
    check_config
    check_private_key
    
    print_info "Setting facet $facet_address for selector $selector..."
    send_admin_call "$ROUTER_ADDRESS" "setFacet(bytes4,address)" "$selector" "$facet_address"
    print_success "Facet update request submitted"
}

# Batch set facets
admin_batch_set_facets() {
    if [ $# -lt 2 ]; then
        print_error "Usage: $0 admin_batch_set_facets <SELECTOR1,SELECTOR2,...> <FACET1,FACET2,...>"
        exit 1
    fi
    check_config
    check_private_key
    
    local selectors="$1"
    local facets="$2"
    
    print_info "Batch setting facets..."
    send_admin_call "$ROUTER_ADDRESS" "batchSetFacet(bytes4[],address[])" "[$selectors]" "[$facets]"
    print_success "Facet batch update request submitted"
}

# ═══════════════════════════════════════════════════════════════════
#  VIEW FACET FUNCTIONS (Read-only)
# ═══════════════════════════════════════════════════════════════════

# Get grid order info
view_get_grid_order() {
    local order_id="$1"
    if [ -z "$order_id" ]; then
        print_error "Usage: $0 view_get_grid_order <ORDER_ID>"
        exit 1
    fi
    check_config
    
    cast call "$ROUTER_ADDRESS" "getGridOrder(uint64)" "$order_id" \
        --rpc-url "$RPC_URL"
}

# Get grid profits
view_get_grid_profits() {
    local grid_id="$1"
    if [ -z "$grid_id" ]; then
        print_error "Usage: $0 view_get_grid_profits <GRID_ID>"
        exit 1
    fi
    check_config
    
    cast call "$ROUTER_ADDRESS" "getGridProfits(uint48)" "$grid_id" \
        --rpc-url "$RPC_URL"
}

# Get grid config
view_get_grid_config() {
    local grid_id="$1"
    if [ -z "$grid_id" ]; then
        print_error "Usage: $0 view_get_grid_config <GRID_ID>"
        exit 1
    fi
    check_config
    
    cast call "$ROUTER_ADDRESS" "getGridConfig(uint48)" "$grid_id" \
        --rpc-url "$RPC_URL"
}

# Get oneshot protocol fee
view_get_oneshot_fee() {
    check_config
    cast call "$ROUTER_ADDRESS" "getOneshotProtocolFeeBps()" --rpc-url "$RPC_URL"
}

# Check if strategy is whitelisted
view_is_strategy_whitelisted() {
    local strategy="$1"
    if [ -z "$strategy" ]; then
        print_error "Usage: $0 view_is_strategy_whitelisted <STRATEGY_ADDRESS>"
        exit 1
    fi
    check_config
    
    cast call "$ROUTER_ADDRESS" "isStrategyWhitelisted(address)" "$strategy" \
        --rpc-url "$RPC_URL"
}

# Get pair tokens
view_get_pair_tokens() {
    local pair_id="$1"
    if [ -z "$pair_id" ]; then
        print_error "Usage: $0 view_get_pair_tokens <PAIR_ID>"
        exit 1
    fi
    check_config
    
    cast call "$ROUTER_ADDRESS" "getPairTokens(uint64)" "$pair_id" \
        --rpc-url "$RPC_URL"
}

# Get pair ID by tokens
view_get_pair_id() {
    local base="$1"
    local quote="$2"
    if [ -z "$base" ] || [ -z "$quote" ]; then
        print_error "Usage: $0 view_get_pair_id <BASE_TOKEN> <QUOTE_TOKEN>"
        exit 1
    fi
    check_config
    
    cast call "$ROUTER_ADDRESS" "getPairIdByTokens(address,address)" "$base" "$quote" \
        --rpc-url "$RPC_URL"
}

# ═══════════════════════════════════════════════════════════════════
#  CANCEL FACET FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

# Cancel entire grid
cancel_grid() {
    local recipient="$1"
    local grid_id="$2"
    local flag="${3:-0}"
    if [ -z "$recipient" ] || [ -z "$grid_id" ]; then
        print_error "Usage: $0 cancel_grid <RECIPIENT> <GRID_ID> [FLAG]"
        print_info "FLAG: 0 = ERC20 (default), 1 = base to ETH, 2 = quote to ETH, 3 = both to ETH"
        exit 1
    fi
    check_config
    check_private_key
    
    print_info "Canceling grid $grid_id..."
    cast send "$ROUTER_ADDRESS" "cancelGrid(address,uint48,uint32)" "$recipient" "$grid_id" "$flag" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "Grid canceled"
}

# Cancel grid orders (range)
cancel_grid_orders_range() {
    local recipient="$1"
    local start_order_id="$2"
    local howmany="$3"
    local flag="${4:-0}"
    if [ -z "$recipient" ] || [ -z "$start_order_id" ] || [ -z "$howmany" ]; then
        print_error "Usage: $0 cancel_grid_orders_range <RECIPIENT> <START_ORDER_ID> <HOWMANY> [FLAG]"
        exit 1
    fi
    check_config
    check_private_key
    
    print_info "Canceling $howmany orders starting from $start_order_id..."
    cast send "$ROUTER_ADDRESS" "cancelGridOrders(address,uint64,uint32,uint32)" \
        "$recipient" "$start_order_id" "$howmany" "$flag" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "Orders canceled"
}

# Cancel grid orders (list)
cancel_grid_orders_list() {
    local grid_id="$1"
    local recipient="$2"
    local id_list="$3"
    local flag="${4:-0}"
    if [ -z "$grid_id" ] || [ -z "$recipient" ] || [ -z "$id_list" ]; then
        print_error "Usage: $0 cancel_grid_orders_list <GRID_ID> <RECIPIENT> <ID_LIST> [FLAG]"
        print_info "ID_LIST: comma-separated order IDs, e.g., '1,2,3'"
        exit 1
    fi
    check_config
    check_private_key
    
    print_info "Canceling orders $id_list from grid $grid_id..."
    cast send "$ROUTER_ADDRESS" "cancelGridOrders(uint48,address,uint64[],uint32)" \
        "$grid_id" "$recipient" "[$id_list]" "$flag" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "Orders canceled"
}

# Withdraw profits
withdraw_profit() {
    local grid_id="$1"
    local to_address="$2"
    local flag="${3:-0}"
    if [ -z "$grid_id" ] || [ -z "$to_address" ]; then
        print_error "Usage: $0 withdraw_profit <GRID_ID> <TO_ADDRESS> [FLAG]"
        exit 1
    fi
    check_config
    check_private_key
    
    print_info "Withdrawing profits from grid $grid_id to $to_address..."
    cast send "$ROUTER_ADDRESS" "withdrawGridProfits(uint48,uint256,address,uint32)" \
        "$grid_id" "0" "$to_address" "$flag" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "Profits withdrawn"
}

# ═══════════════════════════════════════════════════════════════════
#  UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

# Get function selector
get_selector() {
    local sig="$1"
    if [ -z "$sig" ]; then
        print_error "Usage: $0 get_selector <FUNCTION_SIGNATURE>"
        exit 1
    fi
    cast sig "$sig"
}

# Encode calldata
encode_calldata() {
    local sig="$1"
    shift
    if [ -z "$sig" ]; then
        print_error "Usage: $0 encode_calldata <FUNCTION_SIGNATURE> [ARGS...]"
        exit 1
    fi
    cast calldata "$sig" "$@"
}

# Decode calldata
decode_calldata() {
    local sig="$1"
    local calldata="$2"
    if [ -z "$sig" ] || [ -z "$calldata" ]; then
        print_error "Usage: $0 decode_calldata <FUNCTION_SIGNATURE> <CALLDATA>"
        exit 1
    fi
    cast --abi-decode "$sig" "$calldata"
}

# Get owner address
get_owner() {
    check_config
    cast call "$ROUTER_ADDRESS" "owner()" --rpc-url "$RPC_URL" 2>/dev/null || \
        print_info "Note: owner() may not be a registered selector. Check storage directly."
}

# ═══════════════════════════════════════════════════════════════════
#  HELP
# ═══════════════════════════════════════════════════════════════════

show_help() {
    cat << EOF
GridEx Router Facet Call Helper

Environment Variables (set in .env or export):
  RPC_URL         - RPC endpoint URL
  PRIVATE_KEY     - Private key for transactions
  ROUTER_ADDRESS  - GridEx Router contract address
  TIMELOCK_ADDRESS - Optional TimelockController address (defaults to Router owner)
  TIMELOCK_ACTION  - schedule or execute for timelock-owned admin calls (default: schedule)
  TIMELOCK_DELAY   - Optional override for timelock schedule delay in seconds
  TIMELOCK_PREDECESSOR - Timelock predecessor bytes32 (default: zero hash)
  TIMELOCK_SALT    - Timelock salt bytes32 (must match between schedule and execute)

Admin Functions:
  admin_set_weth <WETH_ADDRESS>
  admin_set_quote_token <TOKEN_ADDRESS> <PRIORITY>
  admin_set_strategy_whitelist <STRATEGY_ADDRESS> <true|false>
  admin_set_oneshot_fee <FEE_BPS>
  admin_pause
  admin_unpause
  admin_rescue_eth <TO_ADDRESS> <AMOUNT_WEI>
  admin_transfer_ownership <NEW_OWNER> [both|router|vault]
  admin_set_facet <SELECTOR> <FACET_ADDRESS>
  admin_batch_set_facets <SELECTORS> <FACETS>

View Functions (read-only):
  view_get_grid_order <ORDER_ID>
  view_get_grid_profits <GRID_ID>
  view_get_grid_config <GRID_ID>
  view_get_oneshot_fee
  view_is_strategy_whitelisted <STRATEGY_ADDRESS>
  view_get_pair_tokens <PAIR_ID>
  view_get_pair_id <BASE_TOKEN> <QUOTE_TOKEN>

Cancel Functions:
  cancel_grid <RECIPIENT> <GRID_ID> [FLAG]
  cancel_grid_orders_range <RECIPIENT> <START_ORDER_ID> <HOWMANY> [FLAG]
  cancel_grid_orders_list <GRID_ID> <RECIPIENT> <ID_LIST> [FLAG]
  withdraw_profit <GRID_ID> <TO_ADDRESS> [FLAG]

Utility Functions:
  get_selector <FUNCTION_SIGNATURE>
  encode_calldata <FUNCTION_SIGNATURE> [ARGS...]
  decode_calldata <FUNCTION_SIGNATURE> <CALLDATA>
  get_owner

Examples:
  # Set USDC as quote token with priority 100
  $0 admin_set_quote_token 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 100

  # Schedule a timelock-owned admin call
  TIMELOCK_ACTION=schedule $0 admin_set_quote_token 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 100

  # Execute the same timelock operation after delay
  TIMELOCK_ACTION=execute $0 admin_set_quote_token 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 100

  # Whitelist a strategy
  $0 admin_set_strategy_whitelist 0x1234... true

  # Pause trading
  $0 admin_pause

  # Transfer Router + Vault ownership
  $0 admin_transfer_ownership 0xNewOwner

  # Get grid order info
  $0 view_get_grid_order 123

  # Cancel a grid
  $0 cancel_grid 0xYourAddress 456 0

  # Get function selector
  $0 get_selector "setQuoteToken(address,uint256)"
EOF
}

# Main entry point
case "$1" in
    # Admin functions
    admin_set_weth) shift; admin_set_weth "$@" ;;
    admin_set_quote_token) shift; admin_set_quote_token "$@" ;;
    admin_set_strategy_whitelist) shift; admin_set_strategy_whitelist "$@" ;;
    admin_set_oneshot_fee) shift; admin_set_oneshot_fee "$@" ;;
    admin_pause) shift; admin_pause "$@" ;;
    admin_unpause) shift; admin_unpause "$@" ;;
    admin_rescue_eth) shift; admin_rescue_eth "$@" ;;
    admin_transfer_ownership) shift; admin_transfer_ownership "$@" ;;
    admin_set_facet) shift; admin_set_facet "$@" ;;
    admin_batch_set_facets) shift; admin_batch_set_facets "$@" ;;
    
    # View functions
    view_get_grid_order) shift; view_get_grid_order "$@" ;;
    view_get_grid_profits) shift; view_get_grid_profits "$@" ;;
    view_get_grid_config) shift; view_get_grid_config "$@" ;;
    view_get_oneshot_fee) shift; view_get_oneshot_fee "$@" ;;
    view_is_strategy_whitelisted) shift; view_is_strategy_whitelisted "$@" ;;
    view_get_pair_tokens) shift; view_get_pair_tokens "$@" ;;
    view_get_pair_id) shift; view_get_pair_id "$@" ;;
    
    # Cancel functions
    cancel_grid) shift; cancel_grid "$@" ;;
    cancel_grid_orders_range) shift; cancel_grid_orders_range "$@" ;;
    cancel_grid_orders_list) shift; cancel_grid_orders_list "$@" ;;
    withdraw_profit) shift; withdraw_profit "$@" ;;
    
    # Utility functions
    get_selector) shift; get_selector "$@" ;;
    encode_calldata) shift; encode_calldata "$@" ;;
    decode_calldata) shift; decode_calldata "$@" ;;
    get_owner) shift; get_owner "$@" ;;
    
    # Help
    help|--help|-h) show_help ;;
    *) show_help ;;
esac
