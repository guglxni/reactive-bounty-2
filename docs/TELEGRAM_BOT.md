# 🤖 Telegram Bot (Live Monitoring)

Monitor the Auto-Looper in real-time via Telegram bot with comprehensive position tracking, RVM status monitoring, and automated event notifications.

**Bot Username:** [@reactive_auto_looper_bot](https://t.me/reactive_auto_looper_bot)

---

## 🚀 Quick Start

```bash
# Set environment variables
export TELEGRAM_BOT_TOKEN=your_token_from_botfather
export TELEGRAM_CHAT_ID=your_chat_id

# Navigate to monitor directory
cd monitor

# Install dependencies
npm install

# Start the enhanced bot
node telegram-bot-enhanced.js
```

---

## 📸 Bot Screenshots

> **Live Production Screenshots** - Captured from @reactive_auto_looper_bot running on December 14, 2025

**Gallery (click to enlarge):**

| System Settings | System Status | Position Details |
|----------------|---------------|------------------|
| ![Settings](docs/images/telegram-bot/IMG_4771_thumb.jpg) *`/settings` — system settings and safety features* | ![Status](docs/images/telegram-bot/IMG_4768_thumb.jpg) *`/status` — full system health overview* | ![Position](docs/images/telegram-bot/IMG_4770.jpg) *Position details — leverage, HF, TP/SL* |

| Help & Commands | Inline Buttons | Notifications |
|-----------------|----------------|---------------|
| ![Help](docs/images/telegram-bot/IMG_4771.jpg) *Help — categorized command list* | ![Buttons](docs/images/telegram-bot/IMG_4772.jpg) *Inline buttons — quick actions* | ![Notify](docs/images/telegram-bot/IMG_4775.jpg) *Real-time notifications — loop/unwind events* |

**Additional images:** ![Reserves](docs/images/telegram-bot/IMG_4773.jpg) *Reserves — callback funding status* • ![RVM](docs/images/telegram-bot/IMG_4774.jpg) *RVM status — subscriptions & debt*

### Welcome & Start Screen
The `/start` command provides a welcoming interface with quick action buttons:

**Features Shown:**
- 🤖 Welcome message with key features overview
- 📊 Quick Commands section
- 🔧 Advanced commands preview
- Interactive keyboard buttons (Status, Health, Contracts, Networks, Help)

### Complete Command Reference
The `/help` command displays all available commands organized by category:

**Categories:**
- ━━━ BASIC ━━━ (start, help, status, health)
- ━━━ POSITION ━━━ (position, myposition, leverage, hf, collateral, debt)
- ━━━ ADVANCED ━━━ (tp, fees, settings)
- ━━━ REACTIVE NETWORK ━━━ (reserves, subscription, rvmstatus, rvmdebt, reactive)
- ━━━ MONITORING ━━━ (watch, unwatch, watchlist, setmy)
- ━━━ INFO ━━━ (contracts, networks, features, stats)

### Full System Status
The `/status` command shows comprehensive system health:

**Real-Time Data:**
- 🔷 **AutoLooperManager** (Sepolia)
  - Status: ✅ Active
  - Circuit Breaker: ✅ On
  - Profitability Check: ❌ Off
  - Batch Execution: ✅ On
  - Address: 0x188c...1d47

- 💰 **Callback Reserves**
  - Balance: 0.2000 ETH
  - Status: ✅ Funded

- 📡 **RVM Subscription**
  - Status: ✅ Active

**Interactive Buttons:** 🔄 Refresh | 🏥 Health

### Quick Health Check
The `/health` command provides instant system status:

**Component Status:**
- ✅ Manager: Online
- ✅ Reactive: Online  
- ✅ Reserves: 0.2 ETH
- ⚠️ RVM Debt: 0.0043192 ETH (operational debt)

### System Settings
The `/settings` command displays all configuration:

**Contract State:**
- Paused: ✅ No
- Manager: 0x188c...1d47

**Safety Features:**
- Circuit Breaker: ✅ Enabled
- Profitability Check: ❌ Disabled
- Batch Execution: ✅ Enabled

**Advanced Features:**
- Same-Asset Loop: ✅ Supported
- Flash Loans: ✅ Supported
- TWAP Execution: ✅ Supported
- MEV Protection: ✅ Supported
- Gas Budgets: ✅ Supported
- Take-Profit/Stop-Loss: ✅ Supported

### Contract Addresses
The `/contracts` command lists all deployed contracts:

**Sepolia (Chain ID: 11155111)**
- Manager: 0x188c7b7dC3EEbCA58371abC8D62cB62bEE201d47
- Callback Proxy: 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA
- Funder: 0x9bcbE702215763e2D90BE8f3a374a41a32a0b791

**Lasna (Chain ID: 5318007)**
- Reactive: 0xE58eA8c7eC0E47D195f720f34b3187F59eb27894
- Enhanced: 0x5B8fEc5DBBE29d0B52141e51d407aDf8035bac3A
- System: 0x0000000000000000000000000000000000fffFfF

**RVM ID:** 0x3a949910627c3D424d0871EFa2A34214293A5E25

**Features:** Clickable Etherscan links for contract exploration

### Network Configuration
The `/networks` command shows network details and reactive flow:

**Sepolia (Origin/Destination)**
- Chain ID: 11155111
- RPC: eth-sepolia.g.alchemy.com
- Explorer: sepolia.etherscan.io
- Purpose: Aave V3 leverage looping

**Lasna (Reactive Network)**
- Chain ID: 5318007
- RPC: lasna-rpc.rnk.dev
- Explorer: lasna.rnk.dev
- Purpose: Event monitoring & automation

**Reactive Flow:**
1. User deposits on Sepolia
2. RVM detects PositionUpdated event
3. RSC triggers callback on Sepolia
4. Loop/Unwind step executes

### Callback Reserves
The `/reserves` command monitors callback proxy funding:

**Balance:** 0.200000 ETH  
**Status:** 💚 Healthy  
**RVM ID:** 0x3a94...5E25  
**Proxy Address:** 0xc9f3...7bDA  

**Funding Instructions:** Fund via depositTo(rvmId) on Callback Proxy

### System Statistics
The `/stats` command provides analytics overview:

**Reserves:** 0.2 ETH

**Fees Collected:**
- Loop Fee: 0.001 ETH/op
- Flash Fee: 0.002 ETH/op

**Networks:**
- Sepolia: Chain 11155111
- Lasna: Chain 5318007

*More detailed analytics coming soon!*

---

> **📱 Production Bot:** All screenshots show live data from @reactive_auto_looper_bot  
> **⚡ Real-Time:** Data refreshed on every command  
> **🔒 Secure:** Read-only monitoring, no transaction signing  
> **📊 Interactive:** Inline keyboard buttons for quick actions

---

## 📋 Available Commands

### Basic Commands

| Command | Description | Sample Response |
|---------|-------------|-----------------|
| `/start` | Initialize bot with quick actions | Welcome message + inline buttons |
| `/help` | Full command reference | Categorized command list |
| `/status` | System status overview | Manager state, reserves, RVM status |
| `/health` | Quick component health check | ✅/❌ for each component |
| `/contracts` | All deployed addresses | Manager, Reactive, Proxy addresses |
| `/networks` | Network configuration | Sepolia + Lasna details |

### Position Commands

| Command | Description | Sample Response |
|---------|-------------|-----------------|
| `/position <addr>` | Complete position details | Leverage, HF, state, TP/SL, gas budget |
| `/myposition` | Your position (after `/setmy`) | Same as above for your address |
| `/leverage <addr>` | Current vs target leverage | 2.5x → 3.0x (gap: 0.5x) |
| `/hf <addr>` | Health factor with status | 💚 1.85 - Safe |

### Advanced Features

| Command | Description | Sample Response |
|---------|-------------|-----------------|
| `/tp <addr>` | Take-profit/Stop-loss config | TP: $2500, SL: $2000 |
| `/fees` | Current fee structure | Loop: 0.001 ETH, Flash: 0.002 ETH |
| `/settings` | System settings | Paused, circuit breaker, profitability check |
| `/features` | Complete feature list | All implemented features with status |

### Reactive Network Commands

| Command | Description | Sample Response |
|---------|-------------|-----------------|
| `/reserves` | Callback proxy reserves | 💰 0.0523 ETH - Healthy |
| `/subscription` | RVM subscriptions | 2 active subscriptions |
| `/rvmstatus` | Full RVM status | Debt, balance, subscriptions |
| `/rvmdebt` | RVM debt check | ✅ Clear / ⚠️ 0.005 ETH debt |
| `/reactive` | Reactive contract features | Approval Magic, CRON, Price monitoring |

### Monitoring Commands

| Command | Description | Sample Response |
|---------|-------------|-----------------|
| `/watch <addr>` | Add to watchlist | ✅ Added 0x742d...9999 |
| `/unwatch <addr>` | Remove from watchlist | ✅ Removed from watchlist |
| `/watchlist` | View watchlist | 3 addresses being monitored |
| `/setmy <addr>` | Set your address | ✅ Now you can use /myposition |
| `/stats` | System statistics | Reserves, fees, active positions |

---

## 🔔 Real-Time Notifications

The bot automatically sends notifications for all contract events:

### Position Events
| Event | Notification | When Triggered |
|-------|--------------|----------------|
| `PositionUpdated` | 🔔 Position state change | Every leverage/state update |
| `PositionCreated` | 📦 New position created | User calls `deposit()` |
| `PositionClosed` | ✅ Position fully closed | Unwind completes |

### Execution Events
| Event | Notification | When Triggered |
|-------|--------------|----------------|
| `LoopStepExecuted` | 🔄 Loop iteration complete | Each supply→borrow→swap cycle |
| `UnwindStepExecuted` | ⏪ Unwind step complete | Each withdraw→swap→repay cycle |
| `FlashLeverageExecuted` | ⚡ Flash leverage done | Instant leverage via flash loan |
| `FlashUnwindExecuted` | ⚡ Flash unwind done | Instant unwind via flash loan |

### Safety Events
| Event | Notification | When Triggered |
|-------|--------------|----------------|
| `EmergencyStop` | 🚨 **EMERGENCY!** | Health factor critically low |
| `CircuitBreakerTriggered` | 🔴 Circuit breaker! | Price anomaly detected |
| `GasBudgetExceeded` | ⚠️ Gas limit hit | Position exceeds gas budget |
| `LoopUnprofitable` | 📊 Loop unprofitable | Supply APY < Borrow APY |

### Trading Events
| Event | Notification | When Triggered |
|-------|--------------|----------------|
| `TakeProfitTriggered` | 💰 Take profit! | Price reaches TP target |
| `StopLossTriggered` | 🛑 Stop loss! | Price falls below SL |

---

## 💡 Interactive Features

### Inline Keyboard Buttons

The bot provides quick-action buttons for common operations:

```
┌─────────────┬─────────────┐
│  📊 Status  │  🏥 Health  │
├─────────────┼─────────────┤
│ 📝 Contracts│ 🌐 Networks │
├─────────────┴─────────────┤
│         ❓ Help           │
└───────────────────────────┘
```

### Position Action Buttons

When viewing a position:
```
┌─────────────┬─────────────┐
│  🔄 Refresh │ 📈 Leverage │
├─────────────┴─────────────┤
│        ❤️ Health          │
└───────────────────────────┘
```

---

## 📊 Example Outputs

### `/status` Command
```
📊 System Status

🔷 AutoLooperManager
├ Status: ✅ Active
├ Circuit Breaker: ✅ On
├ Profitability Check: ✅ On
├ Batch Execution: ✅ On
└ 0x188c...1d47

💰 Callback Reserves
├ Balance: 0.0523 ETH
└ Status: ✅ Funded

📡 RVM Subscription
└ Status: ✅ Active
```

### `/position` Command
```
ℹ️ Position Details

👤 User: 0x742d...9999
🔄 State: LOOPING

📊 Leverage
├ Current: 2.50x
├ Target: 3.00x
└ Max Iterations: 10

💎 Assets
├ Collateral: 0xC558...3c (WETH)
├ Borrow: 0x94a9...4C8 (USDC)
└ Initial: 0.01 ETH

🛡️ Safety
├ 💚 Health Factor: 1.85
├ Min HF: 1.10
└ Slippage: 0.50%

⚙️ Settings
├ Flash Loan: ❌
├ Same Asset: ❌
└ Iteration: 3/10

🎯 Take-Profit/Stop-Loss
├ TP Price: Not set
└ SL Price: Not set

⛽ Gas Budget
├ Max: 0.01 ETH
├ Spent: 0.002 ETH
└ TWAP Interval: Disabled
```

### Real-Time Event Notification
```
🔄 Loop Step Executed

👤 0x742d...9999
📈 New Leverage: 2.75x
💰 Supplied: 0.0025 ETH

🔗 View TX
```

---

## ⚙️ Configuration

### Environment Variables

```env
# Required
TELEGRAM_BOT_TOKEN=your_bot_token_from_botfather
TELEGRAM_CHAT_ID=your_chat_id

# Optional (defaults shown)
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/...
REACTIVE_RPC_URL=https://lasna-rpc.rnk.dev
```

### Getting Your Chat ID

1. Start a chat with [@userinfobot](https://t.me/userinfobot)
2. It will reply with your Chat ID
3. Add it to your environment

### Creating a Bot Token

1. Chat with [@BotFather](https://t.me/BotFather)
2. Send `/newbot`
3. Follow prompts to name your bot
4. Copy the token provided

---

## 🔧 NPM Scripts

```bash
# Start enhanced bot (recommended)
node telegram-bot-enhanced.js

# Start basic bot
node telegram-bot.js

# Run comprehensive notification tests
node test-telegram-comprehensive.js
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Telegram Bot Architecture                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │   Telegram   │◀───▶│  Bot Server  │◀───▶│   Sepolia    │    │
│  │     API      │     │ (Node.js)    │     │   Provider   │    │
│  └──────────────┘     └──────┬───────┘     └──────────────┘    │
│                              │                                  │
│                              │                                  │
│                              ▼                                  │
│                       ┌──────────────┐     ┌──────────────┐    │
│                       │   Ethers.js  │◀───▶│    Lasna     │    │
│                       │   Listeners  │     │   Provider   │    │
│                       └──────────────┘     └──────────────┘    │
│                                                                 │
│  Components:                                                    │
│  • Command Handler - Process /commands                          │
│  • Event Listener - Subscribe to contract events                │
│  • Callback Handler - Inline button interactions                │
│  • RNK Client - Query RVM subscriptions                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🌟 Feature Coverage

### Contract Features Exposed

| Feature | Command | Status |
|---------|---------|--------|
| Standard deposit | `/position` shows state | ✅ |
| Same-asset looping | `/position` shows flag | ✅ |
| Advanced deposit | `/position` shows all params | ✅ |
| Flash loans | `/position` shows flash flag | ✅ |
| Take-profit/Stop-loss | `/tp <addr>` | ✅ |
| Gas budget | `/position` shows budget | ✅ |
| TWAP execution | `/position` shows interval | ✅ |
| Circuit breaker | `/status` shows state | ✅ |
| Profitability check | `/status` shows state | ✅ |
| Batch execution | `/status` shows state | ✅ |

### Reactive Features Exposed

| Feature | Command | Status |
|---------|---------|--------|
| RVM subscriptions | `/subscription` | ✅ |
| Callback reserves | `/reserves` | ✅ |
| RVM debt status | `/rvmdebt` | ✅ |
| Approval Magic | `/reactive` | ✅ |
| Price Monitoring | `/reactive` | ✅ |
| CRON Monitoring | `/reactive` | ✅ |
| Liquidation Monitoring | `/reactive` | ✅ |

---

## 🔗 Links

- **Bot:** [@reactive_auto_looper_bot](https://t.me/reactive_auto_looper_bot)
- **Etherscan (Manager):** [View on Sepolia](https://sepolia.etherscan.io/address/0x188c7b7dC3EEbCA58371abC8D62cB62bEE201d47)
- **ReactScan (Reactive):** [View on Lasna](https://lasna.reactscan.net/address/0xE58eA8c7eC0E47D195f720f34b3187F59eb27894)

---

*Part of the Reactive Auto-Looper - Bounty Sprint #2*
