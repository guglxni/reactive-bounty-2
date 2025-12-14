#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#              SOURCIFY VERIFICATION SCRIPT
#         Reactive Network (Lasna) Contract Verification
# ═══════════════════════════════════════════════════════════════
#
# This script specifically handles Sourcify verification for
# contracts deployed on Reactive Network (Lasna chain ID: 5318007)
#
# USAGE:
#   ./script/verify_sourcify.sh                    # Verify all Lasna contracts
#   ./script/verify_sourcify.sh reactive           # Verify AutoLooperReactive only
#   ./script/verify_sourcify.sh funder             # Verify ReactiveFunderRC only
#   ./script/verify_sourcify.sh status             # Check verification status only
#
# KEY INSIGHTS:
# 1. Reactive Network's Sourcify endpoint: https://sourcify.rnk.dev/
# 2. Supported chains: Lasna (5318007), Mainnet (1597), Kopli (5318008)
# 3. Contracts compiled with `via_ir = true` need `--via-ir` flag
# 4. Constructor args must match EXACTLY what was used at deployment
#
# ═══════════════════════════════════════════════════════════════

set -e

# Load environment variables
cd "$(dirname "$0")/.."
source .env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Sourcify endpoint (CORRECT - no /server/ suffix!)
SOURCIFY_URL="https://sourcify.rnk.dev/"

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         SOURCIFY VERIFICATION - REACTIVE NETWORK              ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Sourcify Endpoint:${NC} $SOURCIFY_URL"
echo -e "${BLUE}Chain ID:${NC}          $REACTIVE_CHAIN_ID (Lasna)"
echo ""

# ═══════════════════════════════════════════════════════════════
#                    HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════

check_verification_status() {
    local address=$1
    local name=$2
    
    local status=$(curl -s "https://sourcify.rnk.dev/check-all-by-addresses?addresses=$address&chainIds=$REACTIVE_CHAIN_ID" 2>/dev/null)
    local match_status=$(echo "$status" | jq -r '.[0].chainIds[0].status // .[0].status // "false"' 2>/dev/null)
    
    if [ "$match_status" = "perfect" ]; then
        echo -e "${GREEN}✅ $name: PERFECT MATCH${NC}"
        return 0
    elif [ "$match_status" = "partial" ]; then
        echo -e "${YELLOW}⚠️  $name: PARTIAL MATCH${NC}"
        return 0
    else
        echo -e "${RED}❌ $name: NOT VERIFIED${NC}"
        return 1
    fi
}

verify_auto_looper_reactive() {
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}        Verifying AutoLooperReactive                           ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Address:     $AUTO_LOOPER_REACTIVE"
    echo "Contract:    src/AutoLooperReactive.sol:AutoLooperReactive"
    echo ""
    
    # Constructor: (address _vault, uint256 _chainId)
    # _vault = AutoLooperManager on Sepolia
    # _chainId = Sepolia chain ID (11155111 = 0xaa36a7)
    local CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,uint256)" \
        "$AUTO_LOOPER_MANAGER" \
        "$SEPOLIA_CHAIN_ID")
    
    echo -e "${BLUE}Constructor Parameters:${NC}"
    echo "  _vault (AutoLooperManager): $AUTO_LOOPER_MANAGER"
    echo "  _chainId (Sepolia):         $SEPOLIA_CHAIN_ID"
    echo ""
    echo -e "${BLUE}Encoded Args:${NC} $CONSTRUCTOR_ARGS"
    echo ""
    
    forge verify-contract "$AUTO_LOOPER_REACTIVE" \
        src/AutoLooperReactive.sol:AutoLooperReactive \
        --verifier sourcify \
        --verifier-url "$SOURCIFY_URL" \
        --chain-id "$REACTIVE_CHAIN_ID" \
        --constructor-args "$CONSTRUCTOR_ARGS" \
        --via-ir \
        -vvv
    
    echo ""
    check_verification_status "$AUTO_LOOPER_REACTIVE" "AutoLooperReactive"
}

verify_reactive_funder_rc() {
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}        Verifying ReactiveFunderRC                             ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Address:     $REACTIVE_FUNDER_RC"
    echo "Contract:    src/ReactiveFunderRC.sol:ReactiveFunderRC"
    echo ""
    
    # Constructor: (address _funderContract, address _autoLooperReactive)
    # Both now match the .env values correctly after redeployment on Dec 8, 2025
    
    echo -e "${BLUE}Constructor Parameters:${NC}"
    echo "  _funderContract:       $FUNDER_CONTRACT"
    echo "  _autoLooperReactive:   $AUTO_LOOPER_REACTIVE"
    echo ""
    
    local CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,address)" \
        "$FUNDER_CONTRACT" \
        "$AUTO_LOOPER_REACTIVE")
    
    echo -e "${BLUE}Encoded Args:${NC} $CONSTRUCTOR_ARGS"
    echo ""
    
    forge verify-contract "$REACTIVE_FUNDER_RC" \
        src/ReactiveFunderRC.sol:ReactiveFunderRC \
        --verifier sourcify \
        --verifier-url "$SOURCIFY_URL" \
        --chain-id "$REACTIVE_CHAIN_ID" \
        --constructor-args "$CONSTRUCTOR_ARGS" \
        --via-ir \
        -vvv 2>&1 || true
    
    echo ""
    check_verification_status "$REACTIVE_FUNDER_RC" "ReactiveFunderRC"
}

show_status() {
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              VERIFICATION STATUS SUMMARY                      ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo "Checking verification status..."
    echo ""
    
    echo -e "${CYAN}Reactive Network (Lasna - Chain ID: $REACTIVE_CHAIN_ID):${NC}"
    check_verification_status "$AUTO_LOOPER_REACTIVE" "AutoLooperReactive" || true
    check_verification_status "$REACTIVE_FUNDER_RC" "ReactiveFunderRC" || true
    
    echo ""
    echo -e "${CYAN}Contract Addresses:${NC}"
    echo "  • AutoLooperReactive: $AUTO_LOOPER_REACTIVE"
    echo "  • ReactiveFunderRC:   $REACTIVE_FUNDER_RC"
    echo ""
    echo -e "${CYAN}Sourcify Explorer:${NC}"
    echo "  • AutoLooperReactive: https://sourcify.rnk.dev/#/lookup/$AUTO_LOOPER_REACTIVE"
    echo "  • ReactiveFunderRC:   https://sourcify.rnk.dev/#/lookup/$REACTIVE_FUNDER_RC"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
#                         MAIN
# ═══════════════════════════════════════════════════════════════

case "${1:-all}" in
    reactive|auto|looper)
        verify_auto_looper_reactive
        ;;
    funder|funderrc)
        verify_reactive_funder_rc
        ;;
    status|check)
        show_status
        ;;
    all|*)
        verify_auto_looper_reactive
        echo ""
        verify_reactive_funder_rc
        echo ""
        show_status
        ;;
esac

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}                    VERIFICATION COMPLETE                       ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
