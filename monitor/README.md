# Reactive Auto-Looper Monitor

Real-time monitoring, Telegram bot, and debugging tools for the Reactive Auto-Looper system.

## Overview

This monitoring suite provides comprehensive tools to:
- 🤖 **Telegram Bot** - Interactive bot for position tracking and alerts
- 📊 **Check status** of all system components
- 🔍 **Debug RVM** transactions and logs  
- 👀 **Watch events** in real-time across chains
- 💰 **Manage reserves** for callback proxy
- 🧪 **Run E2E tests** to verify the complete flow

## Quick Start

```bash
# Install dependencies
npm install

# Start Telegram Bot (recommended)
node telegram-bot-enhanced.js

# Check overall system status
npm run status

# Watch events in real-time
npm run watch

# Debug RVM transactions
npm run debug
```

## 🤖 Telegram Bot

The enhanced Telegram bot provides comprehensive monitoring via [@reactive_auto_looper_bot](https://t.me/reactive_auto_looper_bot).

### Starting the Bot

```bash
# Enhanced bot with all features
node telegram-bot-enhanced.js

# Basic bot
node telegram-bot.js
```

### Key Commands

| Command | Description |
|---------|-------------|
| `/status` | System status overview |
| `/position <addr>` | Position details |
| `/hf <addr>` | Health factor check |
| `/reserves` | Callback reserves |
| `/rvmstatus` | RVM status & debt |
| `/help` | All commands |

### Real-Time Notifications

The bot automatically notifies you of:
- 🔄 Loop step executions
- ⏪ Unwind step executions
- 🚨 Emergency stops
- 💰 Take-profit triggers
- 🛑 Stop-loss triggers
- 🔴 Circuit breaker events

**[📖 Full Telegram Bot Documentation](../docs/TELEGRAM_BOT.md)**

---

## Tools

### 1. Status Checker (`check-status.js`)

Quick overview of all system components:

```bash
node check-status.js
```

Shows:
- Sepolia position status
- Lasna RVM status
- Active subscriptions
- Callback proxy reserves
- Recent RVM transactions

### 2. Event Watcher (`watch-events.js`)

Real-time monitoring of events across both chains:

```bash
# Watch all events
node watch-events.js

# Watch only Sepolia
node watch-events.js --sepolia

# Watch only RVM
node watch-events.js --rvm
```

Events monitored:
- `PositionUpdated` on Sepolia
- `LoopStepExecuted` on Sepolia
- RVM transactions on Lasna
- Callback events on Lasna

### 3. RVM Debugger (`debug-rvm.js`)

Deep inspection of RVM state and transactions:

```bash
# Full debug info
node debug-rvm.js

# Debug specific transaction
node debug-rvm.js --tx 3

# Get logs for transaction
node debug-rvm.js --logs 3
```

Shows:
- RVM address mapping
- VM instance info
- Active subscriptions
- Transaction details
- Decoded event logs

### 4. Fund Reserves (`fund-reserves.js`)

Manage callback proxy reserves:

```bash
# Check current reserves
node fund-reserves.js --check

# Fund with default amount (0.1 ETH)
export PRIVATE_KEY="your-key"
node fund-reserves.js

# Fund specific amount
node fund-reserves.js --amount 0.5

# Fund different address
node fund-reserves.js --address 0x...
```

### 5. E2E Test (`e2e-test.js`)

Full end-to-end test of the reactive loop:

```bash
# Dry run (check prerequisites only)
node e2e-test.js --dry-run

# Full E2E test
export PRIVATE_KEY="your-key"
node e2e-test.js
```

Test flow:
1. Check all prerequisites
2. Open new position on Sepolia
3. Wait for RVM reaction on Lasna
4. Wait for callback delivery on Sepolia
5. Verify position state change

## Configuration

The monitoring tools use these contract addresses (in `config.js`):

| Contract | Network | Address |
|----------|---------|---------|
| AutoLooperManager | Sepolia | `0xCfeB5FcD5a71336676F53d7E802422F39955F46A` |
| AutoLooperReactive | Lasna | `0x43E00D80ddc7c49EC9B9c3010c30c870f8D30999` |
| Callback Proxy | Sepolia | `0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA` |
| RVM ID | N/A | `0x3a949910627c3d424d0871efa2a34214293a5e25` |

## Environment Variables

Create a `.env` file for private key:

```env
PRIVATE_KEY=your-private-key-without-0x
```

## Troubleshooting

### "Callback not delivered"

1. Check callback proxy reserves:
   ```bash
   node fund-reserves.js --check
   ```

2. If reserves are 0, fund them:
   ```bash
   node fund-reserves.js --amount 0.1
   ```

### "RVM not reacting"

1. Check subscription status:
   ```bash
   node check-status.js
   ```

2. Debug RVM state:
   ```bash
   node debug-rvm.js
   ```

3. Verify the PositionUpdated topic matches

### "Position not updating"

1. Check that callback proxy is authorized
2. Verify RVM ID matches what the Manager expects
3. Check transaction logs:
   ```bash
   node debug-rvm.js --logs <tx_number>
   ```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      SEPOLIA CHAIN                          │
│                                                             │
│  ┌─────────────────┐    ┌─────────────────────────────┐     │
│  │ AutoLooper      │    │ Callback Proxy               │     │
│  │ Manager         │◄───│ (delivers callbacks)         │     │
│  │                 │    │                               │     │
│  │ - positions     │    │ reserves[rvmId] = ETH       │     │
│  │ - openPosition()│    │                               │     │
│  │ - executeLoop() │    └─────────────────────────────┘     │
│  └────────┬────────┘                ▲                       │
│           │                          │                       │
│   emit PositionUpdated              │ callback               │
│           │                          │                       │
└───────────┼──────────────────────────┼───────────────────────┘
            │                          │
            ▼                          │
┌───────────────────────────────────────────────────────────┐
│                      LASNA (RVM)                          │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ AutoLooperReactive                                   │ │
│  │                                                      │ │
│  │ subscribes to: PositionUpdated events               │ │
│  │                                                      │ │
│  │ react() ──► emits Callback event                    │ │
│  │            (to Manager.executeLoopStep)             │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                           │
│  RVM ID: 0x3a949910627c3d424d0871efa2a34214293a5e25      │
└───────────────────────────────────────────────────────────┘
```

## NPM Scripts

```bash
npm run watch    # Real-time event monitoring
npm run status   # Check all component status
npm run debug    # Debug RVM state
npm run fund     # Fund callback reserves
npm run e2e      # Full E2E test
npm run e2e:dry  # E2E prerequisites check only
```
