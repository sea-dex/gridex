#!/bin/bash
# GridEx Router Facet Call Helper
# This script provides convenient functions to call GridEx Router functions through fallback

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

# Load .env if exists
if [ -f ".env" ]; then
    source .env
fi

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
    cast send "$ROUTER_ADDRESS" "setWETH(address)" "$weth_address" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "WETH set successfully"
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
    cast send "$ROUTER_ADDRESS" "setQuoteToken(address,uint256)" "$token_address" "$priority" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "Quote token set successfully"
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
    cast send "$ROUTER_ADDRESS" "setStrategyWhitelist(address,bool)" "$strategy_address" "$bool_value" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "Strategy whitelist updated"
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
    cast send "$ROUTER_ADDRESS" "setOneshotProtocolFeeBps(uint32)" "$fee_bps" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "Protocol fee updated"
}

# Pause trading
admin_pause() {
    check_config
    check_private_key
    
    print_info "Pausing trading..."
    cast send "$ROUTER_ADDRESS" "pause()" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "Trading paused"
}

# Unpause trading
admin_unpause() {
    check_config
    check_private_key
    
    print_info "Unpausing trading..."
    cast send "$ROUTER_ADDRESS" "unpause()" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "Trading unpaused"
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
    cast send "$ROUTER_ADDRESS" "rescueEth(address,uint256)" "$to_address" "$amount" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "ETH rescued"
}

# Transfer ownership
admin_transfer_ownership() {
    local new_owner="$1"
    if [ -z "$new_owner" ]; then
        print_error "Usage: $0 admin_transfer_ownership <NEW_OWNER_ADDRESS>"
        exit 1
    fi
    check_config
    check_private_key
    
    print_info "Transferring ownership to $new_owner..."
    cast send "$ROUTER_ADDRESS" "transferOwnership(address)" "$new_owner" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "Ownership transferred"
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
    cast send "$ROUTER_ADDRESS" "setFacet(bytes4,address)" "$selector" "$facet_address" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "Facet set"
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
    cast send "$ROUTER_ADDRESS" "batchSetFacet(bytes4[],address[])" \
        "[$selectors]" "[$facets]" \
        --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
    print_success "Facets batch set"
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
    cast send "$ROUTER_ADDRESS" "withdrawProfit(uint48,address,uint32)" \
        "$grid_id" "$to_address" "$flag" \
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

Admin Functions (require owner):
  admin_set_weth <WETH_ADDRESS>
  admin_set_quote_token <TOKEN_ADDRESS> <PRIORITY>
  admin_set_strategy_whitelist <STRATEGY_ADDRESS> <true|false>
  admin_set_oneshot_fee <FEE_BPS>
  admin_pause
  admin_unpause
  admin_rescue_eth <TO_ADDRESS> <AMOUNT_WEI>
  admin_transfer_ownership <NEW_OWNER>
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

  # Whitelist a strategy
  $0 admin_set_strategy_whitelist 0x1234... true

  # Pause trading
  $0 admin_pause

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
