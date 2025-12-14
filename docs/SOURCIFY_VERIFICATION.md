# Sourcify Contract Verification Guide

> **Complete guide for verifying Auto-Looper contracts on Reactive Network's Sourcify instance**

---

## 📋 Overview

All Auto-Looper contracts are now verified on their respective networks:

| Contract | Network | Chain ID | Verifier | Status |
|----------|---------|----------|----------|--------|
| AutoLooperManager | Sepolia | 11155111 | Etherscan | ✅ Verified |
| Funder | Sepolia | 11155111 | Etherscan | ✅ Verified |
| AutoLooperReactive | Lasna | 5318007 | Sourcify | ✅ Perfect Match |
| ReactiveFunderRC | Lasna | 5318007 | Sourcify | ✅ Perfect Match |

---

## 🔗 Contract Addresses

### Sepolia (Etherscan)
```
AutoLooperManager: 0x188c7b7dC3EEbCA58371abC8D62cB62bEE201d47
Funder:            0x9bcbE702215763e2D90BE8f3a374a41a32a0b791
```

### Reactive Network - Lasna (Sourcify)
```
AutoLooperReactive: 0xE58eA8c7eC0E47D195f720f34b3187F59eb27894
ReactiveFunderRC:   0x11E3784cD7A5117EdAC793087814F924639A867e
```

---

## 🌐 Sourcify Endpoints

### Reactive Network's Sourcify Instance

**Base URL:** `https://sourcify.rnk.dev/`

> ⚠️ **Important:** Do NOT use `https://sourcify.rnk.dev/server/` - the `/server/` suffix is incorrect!

### Supported Chains

| Chain Name | Chain ID | RPC Endpoint |
|------------|----------|--------------|
| Reactive Lasna (Testnet) | 5318007 | https://lasna-rpc.rnk.dev |
| Reactive Mainnet | 1597 | https://mainnet-rpc.rnk.dev |
| Reactive Kopli (Testnet) | 5318008 | https://kopli-rpc.rnk.dev |

### API Endpoints

```bash
# Check verification status
GET https://sourcify.rnk.dev/check-all-by-addresses?addresses=<ADDRESS>&chainIds=<CHAIN_ID>

# Get supported chains
GET https://sourcify.rnk.dev/chains

# Verify contract (POST)
POST https://sourcify.rnk.dev/verify

# Check verification job status
GET https://sourcify.rnk.dev/v2/verify/<VERIFICATION_ID>
```

---

## 🛠️ Verification Commands

### Prerequisites

1. Foundry installed with `forge` and `cast`
2. Contract compiled with `via_ir = true` (check `foundry.toml`)
3. Environment variables set (source `.env`)

### Verify AutoLooperReactive

```bash
# Constructor: (address _vault, uint256 _chainId)
CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,uint256)" \
    $AUTO_LOOPER_MANAGER \
    11155111)

forge verify-contract $AUTO_LOOPER_REACTIVE \
    src/AutoLooperReactive.sol:AutoLooperReactive \
    --verifier sourcify \
    --verifier-url https://sourcify.rnk.dev/ \
    --chain-id 5318007 \
    --constructor-args $CONSTRUCTOR_ARGS \
    --via-ir \
    -vvv
```

### Verify ReactiveFunderRC

```bash
# Constructor: (address _funderContract, address _autoLooperReactive)
CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,address)" \
    $FUNDER_CONTRACT \
    $AUTO_LOOPER_REACTIVE)

forge verify-contract $REACTIVE_FUNDER_RC \
    src/ReactiveFunderRC.sol:ReactiveFunderRC \
    --verifier sourcify \
    --verifier-url https://sourcify.rnk.dev/ \
    --chain-id 5318007 \
    --constructor-args $CONSTRUCTOR_ARGS \
    --via-ir \
    -vvv
```

### Verify Sepolia Contracts (Etherscan)

```bash
# AutoLooperManager
CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,address,address,address,address)" \
    $SEPOLIA_CALLBACK_PROXY_ADDR \
    $AAVE_POOL \
    $AAVE_ORACLE \
    $AAVE_PROTOCOL_DATA_PROVIDER \
    $UNISWAP_ROUTER)

forge verify-contract $AUTO_LOOPER_MANAGER \
    src/AutoLooperManager.sol:AutoLooperManager \
    --chain sepolia \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --constructor-args $CONSTRUCTOR_ARGS \
    --via-ir \
    --watch

# Funder (no constructor args)
forge verify-contract $FUNDER_CONTRACT \
    src/Funder.sol:Funder \
    --chain sepolia \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --via-ir \
    --watch
```

---

## 📜 Verification Scripts

Two scripts are provided for automated verification:

### 1. `script/verify_contracts.sh`
Comprehensive verification for all contracts (Sepolia + Lasna):

```bash
./script/verify_contracts.sh
```

### 2. `script/verify_sourcify.sh`
Dedicated Sourcify verification for Reactive Network contracts:

```bash
# Check status only
./script/verify_sourcify.sh status

# Verify AutoLooperReactive
./script/verify_sourcify.sh reactive

# Verify ReactiveFunderRC
./script/verify_sourcify.sh funder

# Verify all
./script/verify_sourcify.sh all
```

---

## 🔍 Checking Verification Status

### Via API

```bash
# Check Sepolia contracts (Etherscan API V2)
curl -s "https://api.etherscan.io/v2/api?chainid=11155111&module=contract&action=getabi&address=<ADDRESS>&apikey=<API_KEY>" | jq '.message'

# Check Lasna contracts (Sourcify)
curl -s "https://sourcify.rnk.dev/check-all-by-addresses?addresses=<ADDRESS>&chainIds=5318007" | jq '.'
```

### Via Explorer

- **Etherscan (Sepolia):** `https://sepolia.etherscan.io/address/<ADDRESS>#code`
- **Sourcify (Lasna):** `https://sourcify.rnk.dev/#/lookup/<ADDRESS>`
- **Reactscan:** `https://lasna.reactscan.net/address/<ADDRESS>`

---

## ⚠️ Common Issues & Solutions

### Issue: "Chain not found" error with public Sourcify
**Solution:** Use Reactive Network's own Sourcify instance at `https://sourcify.rnk.dev/`

### Issue: "Bytecode length mismatch"
**Causes:**
1. Constructor arguments don't match deployment
2. Source code was modified after deployment
3. Compiler settings differ

**Solution:** 
1. Check deployment transaction for actual constructor args
2. Use `cast abi-encode` with exact deployment values
3. Ensure `via_ir = true` matches `foundry.toml`

### Issue: Verification fails silently
**Solution:** Add `-vvvv` flag for verbose output:
```bash
forge verify-contract ... --via-ir -vvvv
```

### Issue: "error decoding response body"
**Cause:** Wrong Sourcify endpoint URL
**Solution:** Use `https://sourcify.rnk.dev/` (not `/server/`)

---

## 📊 Verification Results

### AutoLooperReactive
```json
{
  "isJobCompleted": true,
  "contract": {
    "match": "exact_match",
    "creationMatch": "exact_match",
    "runtimeMatch": "exact_match",
    "chainId": "5318007",
    "address": "0xE58eA8c7eC0E47D195f720f34b3187F59eb27894"
  }
}
```

### ReactiveFunderRC
```json
{
  "isJobCompleted": true,
  "contract": {
    "match": "exact_match",
    "runtimeMatch": "exact_match",
    "chainId": "5318007",
    "address": "0x11E3784cD7A5117EdAC793087814F924639A867e"
  }
}
```

---

## 🔐 Key Compiler Settings

From `foundry.toml`:
```toml
[profile.default]
solc = "0.8.20"
optimizer = true
optimizer_runs = 200
via_ir = true          # CRITICAL: Must use --via-ir flag when verifying
```

> **Note:** When `via_ir = true`, always pass `--via-ir` to `forge verify-contract`

---

## 📚 References

- [Sourcify Documentation](https://docs.sourcify.dev/)
- [Reactive Network Docs](https://dev.reactive.network)
- [Foundry Verification Guide](https://book.getfoundry.sh/forge/deploying#verifying-a-contract)
- [Etherscan API V2](https://docs.etherscan.io/v/sepolia-etherscan/)
