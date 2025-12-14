#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#                CONTRACT VERIFICATION SCRIPT
#              Auto-Looper for Reactive Bounty 2.0
# ═══════════════════════════════════════════════════════════════
# 
# This script verifies deployed contracts on Etherscan (Sepolia)
# and Sourcify (Reactive Network Lasna).
#
# KEY INSIGHTS:
# 1. Contracts compiled with `via_ir = true` MUST use the 
#    `--via-ir` flag when verifying
# 2. Reactive Network's Sourcify is at https://sourcify.rnk.dev/
#    (NOT https://sourcify.rnk.dev/server/)
# 3. ReactiveFunderRC was deployed with different constructor args
#    than current .env - it points to an older AutoLooperReactive
#
# ═══════════════════════════════════════════════════════════════

set -e

# Load environment variables
source .env

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           CONTRACT VERIFICATION SCRIPT                        ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Sourcify endpoint for Reactive Network (CORRECT - no /server/ suffix!)
REACTIVE_SOURCIFY="https://sourcify.rnk.dev/"

# ═══════════════════════════════════════════════════════════════
#                    SEPOLIA CONTRACTS
# ═══════════════════════════════════════════════════════════════

echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}                    SEPOLIA CONTRACTS                          ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Verify AutoLooperManager
echo -e "${GREEN}[1/2] Verifying AutoLooperManager...${NC}"
echo "     Address: $AUTO_LOOPER_MANAGER"

# Encode constructor arguments
MANAGER_CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,address,address,address,address)" \
    $SEPOLIA_CALLBACK_PROXY_ADDR \
    $AAVE_POOL \
    $AAVE_ORACLE \
    $AAVE_PROTOCOL_DATA_PROVIDER \
    $UNISWAP_ROUTER)

forge verify-contract $AUTO_LOOPER_MANAGER \
    src/AutoLooperManager.sol:AutoLooperManager \
    --chain sepolia \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --constructor-args $MANAGER_CONSTRUCTOR_ARGS \
    --via-ir \
    --watch || echo -e "${YELLOW}Already verified or verification pending${NC}"

echo ""

# Verify Funder
echo -e "${GREEN}[2/2] Verifying Funder...${NC}"
echo "     Address: $FUNDER_CONTRACT"

forge verify-contract $FUNDER_CONTRACT \
    src/Funder.sol:Funder \
    --chain sepolia \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --via-ir \
    --watch || echo -e "${YELLOW}Already verified or verification pending${NC}"

echo ""

# ═══════════════════════════════════════════════════════════════
#                  REACTIVE NETWORK CONTRACTS
# ═══════════════════════════════════════════════════════════════

echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}              REACTIVE NETWORK CONTRACTS (Lasna)               ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${BLUE}Using Sourcify endpoint: $REACTIVE_SOURCIFY${NC}"
echo ""

# Verify AutoLooperReactive on Sourcify
echo -e "${GREEN}[1/2] Verifying AutoLooperReactive on Sourcify...${NC}"
echo "     Address: $AUTO_LOOPER_REACTIVE"
echo "     Chain ID: $REACTIVE_CHAIN_ID (Lasna)"

# Constructor: (address _vault, uint256 _chainId)
REACTIVE_CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,uint256)" \
    $AUTO_LOOPER_MANAGER \
    $SEPOLIA_CHAIN_ID)

echo "     Constructor Args: $REACTIVE_CONSTRUCTOR_ARGS"

forge verify-contract $AUTO_LOOPER_REACTIVE \
    src/AutoLooperReactive.sol:AutoLooperReactive \
    --verifier sourcify \
    --verifier-url $REACTIVE_SOURCIFY \
    --chain-id $REACTIVE_CHAIN_ID \
    --constructor-args $REACTIVE_CONSTRUCTOR_ARGS \
    --via-ir || echo -e "${YELLOW}Verification submitted or already verified${NC}"

echo ""

# Verify ReactiveFunderRC on Sourcify
echo -e "${GREEN}[2/2] Verifying ReactiveFunderRC on Sourcify...${NC}"
echo "     Address: $REACTIVE_FUNDER_RC"

# Constructor: (address _funderContract, address _autoLooperReactive)
# Redeployed Dec 8, 2025 with correct constructor args
FUNDER_RC_CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,address)" \
    $FUNDER_CONTRACT \
    $AUTO_LOOPER_REACTIVE)

echo "     Constructor Args: $FUNDER_RC_CONSTRUCTOR_ARGS"

forge verify-contract $REACTIVE_FUNDER_RC \
    src/ReactiveFunderRC.sol:ReactiveFunderRC \
    --verifier sourcify \
    --verifier-url $REACTIVE_SOURCIFY \
    --chain-id $REACTIVE_CHAIN_ID \
    --constructor-args $FUNDER_RC_CONSTRUCTOR_ARGS \
    --via-ir 2>&1 || echo -e "${YELLOW}Verification submitted or already verified${NC}"

echo ""

# ═══════════════════════════════════════════════════════════════
#                    VERIFICATION STATUS CHECK
# ═══════════════════════════════════════════════════════════════

echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}                   VERIFICATION STATUS                         ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check Sepolia contracts via Etherscan API V2
echo "Checking Sepolia contracts via Etherscan API V2..."

MANAGER_STATUS=$(curl -s "https://api.etherscan.io/v2/api?chainid=11155111&module=contract&action=getabi&address=$AUTO_LOOPER_MANAGER&apikey=$ETHERSCAN_API_KEY" | jq -r '.message' 2>/dev/null || echo "ERROR")
FUNDER_STATUS=$(curl -s "https://api.etherscan.io/v2/api?chainid=11155111&module=contract&action=getabi&address=$FUNDER_CONTRACT&apikey=$ETHERSCAN_API_KEY" | jq -r '.message' 2>/dev/null || echo "ERROR")

# Check Reactive Network contracts via Sourcify API
echo "Checking Reactive Network contracts via Sourcify..."

REACTIVE_STATUS=$(curl -s "https://sourcify.rnk.dev/check-all-by-addresses?addresses=$AUTO_LOOPER_REACTIVE&chainIds=$REACTIVE_CHAIN_ID" | jq -r '.[0].status' 2>/dev/null || echo "ERROR")
FUNDER_RC_STATUS=$(curl -s "https://sourcify.rnk.dev/check-all-by-addresses?addresses=$REACTIVE_FUNDER_RC&chainIds=$REACTIVE_CHAIN_ID" | jq -r '.[0].status' 2>/dev/null || echo "ERROR")

echo ""
echo "┌─────────────────────────────────────────────────────────────────────────┐"
echo "│ Contract              │ Network  │ Status                              │"
echo "├─────────────────────────────────────────────────────────────────────────┤"

if [ "$MANAGER_STATUS" = "OK" ]; then
    echo -e "│ AutoLooperManager     │ Sepolia  │ ${GREEN}✅ Verified${NC}                         │"
else
    echo -e "│ AutoLooperManager     │ Sepolia  │ ${RED}❌ Not Verified${NC}                      │"
fi

if [ "$FUNDER_STATUS" = "OK" ]; then
    echo -e "│ Funder                │ Sepolia  │ ${GREEN}✅ Verified${NC}                         │"
else
    echo -e "│ Funder                │ Sepolia  │ ${RED}❌ Not Verified${NC}                      │"
fi

if [ "$REACTIVE_STATUS" = "perfect" ] || [ "$REACTIVE_STATUS" = "partial" ]; then
    echo -e "│ AutoLooperReactive    │ Lasna    │ ${GREEN}✅ Verified ($REACTIVE_STATUS)${NC}              │"
else
    echo -e "│ AutoLooperReactive    │ Lasna    │ ${RED}❌ Not Verified${NC}                      │"
fi

if [ "$FUNDER_RC_STATUS" = "perfect" ] || [ "$FUNDER_RC_STATUS" = "partial" ]; then
    echo -e "│ ReactiveFunderRC      │ Lasna    │ ${GREEN}✅ Verified ($FUNDER_RC_STATUS)${NC}              │"
else
    echo -e "│ ReactiveFunderRC      │ Lasna    │ ${RED}❌ Not Verified${NC}                      │"
fi

echo "└─────────────────────────────────────────────────────────────────────────┘"
echo ""
echo "Contract Explorer Links:"
echo "  Sepolia (Etherscan):"
echo "    • AutoLooperManager: https://sepolia.etherscan.io/address/$AUTO_LOOPER_MANAGER#code"
echo "    • Funder:            https://sepolia.etherscan.io/address/$FUNDER_CONTRACT#code"
echo ""
echo "  Reactive Network (Sourcify):"
echo "    • AutoLooperReactive: https://sourcify.rnk.dev/#/lookup/$AUTO_LOOPER_REACTIVE"
echo "    • ReactiveFunderRC:   https://sourcify.rnk.dev/#/lookup/$REACTIVE_FUNDER_RC"
echo ""
echo "Reactscan Links:"
echo "  • AutoLooperReactive: https://lasna.reactscan.net/address/$AUTO_LOOPER_REACTIVE"
echo "  • ReactiveFunderRC:   https://lasna.reactscan.net/address/$REACTIVE_FUNDER_RC"
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              VERIFICATION COMPLETE!                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
