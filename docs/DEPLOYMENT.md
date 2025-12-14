# Auto-Looper Deployment Guide

## Deployed Contracts (E2E TESTED ✅)

### Latest Testnet Deployment (Sepolia + Lasna)

| Contract | Network | Address | Status |
|----------|---------|---------|--------|
| AutoLooperManager | Sepolia (11155111) | `0x188c7b7dC3EEbCA58371abC8D62cB62bEE201d47` | ✅ E2E Working |
| AutoLooperReactive | Lasna (5318007) | `0xE58eA8c7eC0E47D195f720f34b3187F59eb27894` | ✅ E2E Working |
| Funder | Sepolia (11155111) | `0x9bcbE702215763e2D90BE8f3a374a41a32a0b791` | ✅ Deployed |
| ReactiveFunderRC | Lasna (5318007) | `0xa8D3bC8A55Cf854b3184C6bEaF09aE795De02ADC` | ✅ Deployed |

### E2E Test Results (Dec 6, 2025)

**Successful automated loop iteration:**
- **Deposit tx**: `0xcc9505415cd0f7ec0cdfb5b1f629e9e3787ede4c09235444bfbe9e22f92f6613` (block 9781385)
- **Automated callback tx**: `0x194ad24c00e0a9b17e3ae53be8ff32cd0b53069e24169072334c8f5b1f7b7ec4` (block 9781386)
- User deposited 0.001 WETH, target 1.5x leverage
- Reactive Network detected `PositionUpdated` event
- Callback executed `executeLoopStep` automatically
- Final leverage achieved: 4.04x (exceeded target)
- Position auto-stopped in IDLE state

### Contract Verification Status

| Contract | Verification | Notes |
|----------|--------------|-------|
| AutoLooperManager | ⏳ Pending | Bytecode mismatch due to `via_ir=true` |
| AutoLooperReactive | ⏳ Pending | Use Sourcify for Reactive Network |
| Funder | ⏳ Pending | Bytecode mismatch due to `via_ir=true` |
| ReactiveFunderRC | ⏳ Pending | Use Sourcify for Reactive Network |

**Note on Verification:** Etherscan verification fails with "bytecode mismatch" because we compile with `via_ir=true` for gas optimization. The Foundry compiler produces different bytecode than Etherscan's verification system expects. Options:
1. Disable `via_ir` and redeploy (loses optimization)
2. Use `forge verify-contract` with `--via-ir` flag (may still mismatch)
3. Verify via Sourcify which supports IR compilation
4. Submit flattened source with compiler settings

### Key Addresses

| Name | Address | Description |
|------|---------|-------------|
| Deployer/RVM ID | `0x3a949910627c3D424d0871EFa2A34214293A5E25` | RSC deployer address (used as RVM ID) |
| User Wallet | `0xDDe9D31a31d6763612C7f535f51E5dC9f830682e` | Contract owner & test user |
| Callback Proxy | `0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA` | Sepolia callback sender |
| System Contract | `0x0000000000000000000000000000000000fffFfF` | Reactive Network system |

### DeFi Protocol Addresses (Sepolia)

| Protocol | Contract | Address |
|----------|----------|---------|
| Aave V3 | Pool | `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951` |
| Aave V3 | Oracle | `0x2da88497588bf89281816106C7259e31aF45a663` |
| Aave V3 | Data Provider | `0x3e9708d80f7B3e43118013075F7e95CE3AB31F31` |
| Aave V3 | Faucet | `0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D` |
| Uniswap V2 | Router | `0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008` |
| Uniswap V2 | Factory | `0x7E0987E5b3a30e3f2828572Bb659A548460a3003` |

### Token Addresses (Sepolia)

| Token | Address |
|-------|---------|
| WETH | `0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c` |
| LINK | `0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBE5` |
| USDC | `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8` |
| WETH/LINK Pair | `0xb4c620bc93c57935cb67718ab07015602442b6b1` |

## Deployment Steps

### Prerequisites

1. **Get REACT tokens**: Send SepETH to the faucet on Sepolia:
   ```bash
   cast send 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 --value 0.5ether --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
   ```
   You'll receive ~50 REACT on Lasna (100 REACT per 1 SepETH, max 5 SepETH).

2. **Set up .env** with required variables (see `.env.example`)

### Step 1: Deploy AutoLooperManager on Sepolia

```bash
forge create --broadcast \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $SEPOLIA_PRIVATE_KEY \
  src/AutoLooperManager.sol:AutoLooperManager \
  --constructor-args $SEPOLIA_CALLBACK_PROXY_ADDR $AAVE_POOL $AAVE_ORACLE $AAVE_PROTOCOL_DATA_PROVIDER $UNISWAP_ROUTER
```

### Step 2: Deploy AutoLooperReactive on Lasna

```bash
forge create --broadcast \
  --rpc-url $REACTIVE_RPC_URL \
  --private-key $PRIVATE_KEY \
  src/AutoLooperReactive.sol:AutoLooperReactive \
  --value 0.5ether \
  --constructor-args $AUTO_LOOPER_MANAGER 11155111
```

Note: Use the same private key for both deployments or the one that has REACT tokens.

### Step 3: Set RVM ID on Manager

**IMPORTANT**: The RVM ID must be the **deployer address**, NOT the reactive contract address!

```bash
# Use the DEPLOYER address (the address that deployed AutoLooperReactive)
cast send \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $SEPOLIA_PRIVATE_KEY \
  $AUTO_LOOPER_MANAGER \
  "setRvmId(address)" $DEPLOYER_ADDRESS
```

**Why?** The Reactive Network replaces the first 160 bits of callback payloads with the **deployer's address**, not the contract address. If you use the wrong address, callbacks will fail with "Authorized RVM ID only".

### Step 4: Fund Manager Contract

```bash
cast send \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $SEPOLIA_PRIVATE_KEY \
  $AUTO_LOOPER_MANAGER \
  --value 0.1ether
```

## Verification

### Check Deployment

```bash
# Manager owner
cast call $AUTO_LOOPER_MANAGER "owner()" --rpc-url $SEPOLIA_RPC_URL

# Reactive vault address
cast call $AUTO_LOOPER_REACTIVE "getVault()" --rpc-url $REACTIVE_RPC_URL

# Reactive chain ID
cast call $AUTO_LOOPER_REACTIVE "getChainId()" --rpc-url $REACTIVE_RPC_URL

# Balances
cast balance $AUTO_LOOPER_MANAGER --rpc-url $SEPOLIA_RPC_URL
cast balance $AUTO_LOOPER_REACTIVE --rpc-url $REACTIVE_RPC_URL
```

## Architecture Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          User Interaction                                │
│                                                                         │
│  1. User calls deposit() on AutoLooperManager (Sepolia)                │
│  2. Manager emits PositionUpdated event                                 │
│  3. Reactive Network monitors the event                                 │
│  4. AutoLooperReactive processes and emits Callback                     │
│  5. Callback executes executeLoopStep() on Manager                      │
│  6. Loop continues until target leverage reached                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

Sepolia                          Reactive Network (Lasna)
┌────────────────────┐           ┌────────────────────────┐
│ AutoLooperManager  │◄──────────│ AutoLooperReactive     │
│                    │  Callback │                        │
│ - deposit()        │           │ - react() to events    │
│ - executeLoopStep()│           │ - emit Callback        │
│ - executeUnwind()  │           │                        │
│                    │           │                        │
│ Events:            │──────────►│ Subscription:          │
│ PositionUpdated    │  Monitor  │ topic_0 = 0xd97440...  │
└────────────────────┘           └────────────────────────┘
```

## Event Topic

PositionUpdated event signature:
```
keccak256("PositionUpdated(address,uint256,uint256,uint256,uint256,uint8)")
= 0xd97440db9c04f33925d0d4f3a9762d3e70c867b5d7e193cb11897e63c88f10de
```

## Gas Requirements

- **Manager (Sepolia)**: ~0.1 ETH for callback execution
- **Reactive (Lasna)**: ~0.5 REACT for subscription and callbacks

## Troubleshooting

### "Authorized RVM ID only" on callbacks
The RVM ID is set incorrectly. It must be the **deployer address**, not the reactive contract address:
```bash
cast send $AUTO_LOOPER_MANAGER "setRvmId(address)" $DEPLOYER_ADDRESS \
  --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

### "Insufficient funds" on Lasna
Get more REACT from the faucet by sending SepETH to `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`.

### Position stuck in EMERGENCY state at 1x leverage
If a position is in EMERGENCY/UNWINDING state but already at 1x leverage (no debt), use:
```bash
cast send $AUTO_LOOPER_MANAGER "closePosition()" \
  --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

### Owner needs to rescue stuck collateral
In extreme edge cases, the owner can withdraw collateral from Aave:
```bash
cast send $AUTO_LOOPER_MANAGER "emergencyAaveWithdraw(address,address,uint256)" \
  $WETH $USER_ADDRESS $(cast --max-uint256) \
  --rpc-url $SEPOLIA_RPC_URL --private-key $OWNER_PRIVATE_KEY
```

### "Authorized RVM ID only" error
Call `setRvmId(reactiveContractAddress)` on the Manager contract.

### Subscription fails
Ensure the reactive contract has sufficient REACT balance (>0.1 REACT).
