# Reactive Auto-Looper: Automated Leveraged Looping

## Bounty Submission: Sprint #2 - Automation Use Case

A production-grade, autonomous leveraged looping system built on Aave V3 that uses Reactive Network contracts to automatically execute supply→borrow→swap→supply cycles to achieve target leverage, with continuous health factor monitoring and emergency protection. Features a comprehensive Telegram bot for live monitoring and position tracking.

| | |
|-----------------|------------------------------------------------------------------------|
| **Deadline**    | December 14, 2025                                                      |
| **Status**      | ✅ **FULLY OPERATIONAL**                                               |
| **Tests**       | 252 tests passing                                                      |
| **Networks**    | Sepolia (Origin/Destination) + Lasna (Reactive)                       |
| **Last Verified** | December 14, 2025 - E2E automation confirmed working                  |

---

## 🎬 Demo Video

[![Reactive Auto-Looper Demo](https://img.youtube.com/vi/PENDING/maxresdefault.jpg)](#)

[▶️ Watch the Full Demo on YouTube](#) *(Recording pending)*

📋 **Demo Script Available:** [docs/DEMO_VIDEO_SCRIPT.md](docs/DEMO_VIDEO_SCRIPT.md)

---

## 🎯 Deployed Contracts (Production - Testnet)

| Contract | Network | Chain ID | Address |
|----------|---------|----------|---------|
| AutoLooperManager | Sepolia | 11155111 | `0x188c7b7dC3EEbCA58371abC8D62cB62bEE201d47` |
| AutoLooperReactive | Lasna | 5318007 | `0xE58eA8c7eC0E47D195f720f34b3187F59eb27894` |
| AutoLooperReactiveEnhanced | Lasna | 5318007 | `0x5B8fEc5DBBE29d0B52141e51d407aDf8035bac3A` |
| Funder | Sepolia | 11155111 | `0x9bcbE702215763e2D90BE8f3a374a41a32a0b791` |
| ReactiveFunderRC | Lasna | 5318007 | `0xa8D3bC8A55Cf854b3184C6bEaF09aE795De02ADC` |
| Callback Proxy | Sepolia | 11155111 | `0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA` |

### DeFi Protocol Addresses (Sepolia)

| Protocol | Contract | Address |
|----------|----------|---------|
| Aave V3 | Pool | `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951` |
| Aave V3 | Oracle | `0x2da88497588bf89281816106C7259e31AF45a663` |
| Aave V3 | Data Provider | `0x3e9708d80f7B3e43118013075F7e95CE3AB31F31` |
| Uniswap V2 | Router | `0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008` |
| Token | WETH | `0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c` |
| Token | USDC | `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8` |

---

## 📊 Sample Transaction Hashes (E2E Verified)

### Successful Automated Loop Iteration

| Step | Transaction Hash | Block |
|------|------------------|-------|
| **Deposit** | [`0xcc9505415cd0f7ec0cdfb5b1f629e9e3787ede4c09235444bfbe9e22f92f6613`](https://sepolia.etherscan.io/tx/0xcc9505415cd0f7ec0cdfb5b1f629e9e3787ede4c09235444bfbe9e22f92f6613) | 9781385 |
| **Automated Callback** | [`0x194ad24c00e0a9b17e3ae53be8ff32cd0b53069e24169072334c8f5b1f7b7ec4`](https://sepolia.etherscan.io/tx/0x194ad24c00e0a9b17e3ae53be8ff32cd0b53069e24169072334c8f5b1f7b7ec4) | 9781386 |

**Result:** User deposited 0.001 WETH with target 1.5x leverage → RSC detected `PositionUpdated` event → Callback executed `executeLoopStep` automatically → Final leverage: 4.04x → Position auto-stopped in IDLE state

---

## 🤖 Telegram Bot (Live Monitoring)

Monitor the Auto-Looper in real-time via Telegram bot with comprehensive position tracking and automated event notifications. **[📖 Full Documentation](docs/TELEGRAM_BOT.md)**

### Quick Start

```bash
# Set environment variables
export TELEGRAM_BOT_TOKEN=your_token_from_botfather
export TELEGRAM_CHAT_ID=your_chat_id

# Start the bot
cd monitor && node telegram-bot-enhanced.js
```

### Available Commands

| Command | Description | Sample Response |
|---------|-------------|-----------------|
| `/status` | Full system status | Manager state, reserves, RVM health |
| `/position <addr>` | Position details | Leverage, HF, state, TP/SL |
| `/hf <addr>` | Health factor check | 💚 1.85 - Safe |
| `/reserves` | Callback proxy reserves | 💰 0.0523 ETH |
| `/rvmstatus` | RVM status & debt | Subscriptions, debt check |
| `/features` | Feature overview | All implemented features |
| `/help` | All commands | Full command reference |

### Bot Screenshots

| System Status | Position Details |
|---------------|------------------|
| ![Status](docs/images/telegram-bot/bot-status.png) | ![Position](docs/images/telegram-bot/bot-position.png) |
| `/status` - Full system health | `/position <addr>` - Leverage & HF |

---

## 🔄 How It Works (Cross-Chain Workflow)

### Step 1: User Deposit (Sepolia)

User calls `deposit()` on AutoLooperManager with collateral and target leverage:

```solidity
manager.deposit{value: 0.001 ether}(
    WETH,        // collateral asset
    USDC,        // borrow asset  
    1 ether,     // amount
    3e18,        // 3x target leverage
    10,          // max iterations
    false        // iterative mode
);
```

This emits a `PositionUpdated` event that the RSC subscribes to.

### Step 2: Reactive Processing (Lasna - Chain 5318007)

The RSC (AutoLooperReactive) subscribes to `PositionUpdated` events and autonomously:

1. Validates incoming position data
2. Checks health factor against minimum threshold (1.1)
3. Determines if more looping is needed (currentLeverage < targetLeverage)
4. Emits a `Callback` event to trigger the next step

```
RSC: 0xE58eA8c7eC0E47D195f720f34b3187F59eb27894
```

### Step 3: Loop Execution (Sepolia)

The Callback Proxy delivers the callback to AutoLooperManager, which:

1. Validates sender (Callback Proxy only)
2. Validates RVM ID (authorized deployer only)
3. Borrows against collateral from Aave
4. Swaps borrowed asset back to collateral
5. Supplies collateral back to Aave
6. Emits new `PositionUpdated` event (triggers next iteration)

### Step 4: Repeat Until Target

The cycle continues until:
- ✅ Target leverage reached → State changes to IDLE
- ⚠️ Health factor drops → Emergency unwind triggered
- ⚠️ Max iterations reached → Loop stops
- ⚠️ Liquidity unavailable → Graceful failure with detailed events

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SEPOLIA (Chain 11155111)                           │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  AutoLooperManager.sol                                                 │ │
│  │  - deposit() initiates loop                                            │ │
│  │  - executeLoopStep() executes supply→borrow→swap→supply               │ │
│  │  - executeUnwindStep() reduces leverage                                │ │
│  │  Emits: PositionUpdated(user, currentLev, targetLev, healthFactor)     │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ Event Subscription (PositionUpdated)
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         REACTIVE LASNA (Chain 5318007)                       │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  AutoLooperReactive.sol (RSC)                                          │ │
│  │  0xE58eA8c7eC0E47D195f720f34b3187F59eb27894                            │ │
│  │                                                                        │ │
│  │  • Subscribes to PositionUpdated events                                │ │
│  │  • STATELESS design - all decisions from event data                    │ │
│  │  • Health Factor Guardian - auto-unwind if HF < 1.1                    │ │
│  │  • Emits Callback event to destination                                 │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ Callback Event
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SEPOLIA (Chain 11155111)                           │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  Callback Proxy: 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA            │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                      │                                       │
│                                      ▼                                       │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  AutoLooperManager - executeLoopStep() / executeUnwindStep()           │ │
│  │  • Security: dual authorization (Callback Proxy + RVM ID)              │ │
│  │  • Executes Aave supply/borrow/withdraw/repay                          │ │
│  │  • Executes Uniswap swaps with slippage protection                     │ │
│  │  • Emits PositionUpdated → triggers next RSC reaction                  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔋 Reactivate: Self-Sustaining Gas System (Deployed)

A comprehensive on-chain solution for automated RSC funding - implementing the [Reactivate pattern](https://blog.reactive.network/reactivate-automated-monitoring-and-funding-for-reactive-contracts/).

### Deployed Addresses

| Contract | Network | Address |
|----------|---------|---------|
| Funder | Sepolia | `0x9bcbE702215763e2D90BE8f3a374a41a32a0b791` |
| ReactiveFunderRC | Lasna | `0xa8D3bC8A55Cf854b3184C6bEaF09aE795De02ADC` |

### Components

| Contract | Purpose |
|----------|---------|
| `Funder.sol` | Collects fees, bridges funds to RSC via Callback Proxy |
| `ReactiveFunderRC.sol` | Monitors FundsReceived events, triggers coverDebt() |

### How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  1. User pays fee during loop operations (0.1% of deposit)                  │
│                                                                              │
│  2. Funder.sol receives ETH and emits FundsReceived event                   │
│     └── Funder: 0x9bcbE702215763e2D90BE8f3a374a41a32a0b791                  │
│                                                                              │
│  3. ReactiveFunderRC detects event and triggers callback                    │
│     └── ReactiveFunderRC: 0xa8D3bC8A55Cf854b3184C6bEaF09aE795De02ADC        │
│                                                                              │
│  4. Funder.coverDebt() bridges funds via Callback Proxy                     │
│     └── Calls: CallbackProxy.depositTo(targetRsc)                           │
│                                                                              │
│  5. RSC balance is replenished automatically                                │
│     └── AutoLooperReactive stays funded for continuous operation            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Installation

```bash
# Clone repository
git clone <repo-url>
cd reactive-auto-looper

# Install dependencies
forge install

# Copy environment
cp .env.example .env
# Edit .env with your keys
```

### Run Tests

```bash
# Run all tests (252 tests)
forge test

# With summary
forge test --summary

# Expected output:
# ╭────────────────────────────────+────────+────────+---------╮
# │ Test Suite                     │ Passed │ Failed │ Skipped │
# ├────────────────────────────────┼────────┼────────┼---------┤
# │ FullSystemE2ETest              │ 26     │ 0      │ 0       │
# │ FunderIntegrationTest          │ 30     │ 0      │ 0       │
# │ AutoLooperForkTest             │ 15     │ 0      │ 0       │
# │ EnhancedCallbacksForkTest      │ 26     │ 0      │ 0       │
# │ AutoLooperReactiveEnhancedTest │ 23     │ 0      │ 0       │
# │ + 9 more suites                │ ...    │ ...    │ ...     │
# │ TOTAL                          │ 252    │ 0      │ 0       │
# ╰────────────────────────────────┴────────┴────────┴---------╯
```

### Deploy (Sepolia + Lasna)

```bash
# 1. Get REACT tokens (send SepETH to faucet)
cast send 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 \
  --value 0.5ether \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY

# 2. Deploy Manager on Sepolia
forge script script/DeployManager.s.sol:DeployManager \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast

# 3. Deploy Reactive on Lasna
forge script script/DeployReactive.s.sol:DeployReactive \
  --rpc-url $REACTIVE_RPC_URL \
  --broadcast

# 4. Set RVM ID on Manager (IMPORTANT: use deployer address!)
cast send $MANAGER "setRvmId(address)" $DEPLOYER_ADDRESS \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

### Start a Loop

```bash
# Deposit WETH with 3x target leverage
cast send $MANAGER "deposit(address,address,uint256,uint256,uint256,bool)" \
  $WETH $USDC 0.01ether 3000000000000000000 10 false \
  --value 0.001ether \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

---

## 📁 Project Structure

```
src/
├── AutoLooperManager.sol           # Main callback contract (Sepolia) - 1,900 lines
├── AutoLooperReactive.sol          # Reactive contract (Lasna) - 376 lines
├── AutoLooperReactiveEnhanced.sol  # Enhanced RSC with CRON/Price monitoring - 1,360 lines
├── Funder.sol                      # Self-sustaining gas collector - 327 lines
├── ReactiveFunderRC.sol            # Reactive funder (Lasna) - 283 lines
├── interfaces/
│   ├── IAutoLooper.sol             # Main interface with events - 346 lines
│   ├── IAavePool.sol               # Aave V3 Pool interface
│   ├── IAaveOracle.sol             # Aave price oracle interface
│   ├── IAaveProtocolDataProvider.sol # Aave data provider
│   ├── IFlashLoanReceiver.sol      # Aave flash loan callback
│   └── IUniswapV2Router.sol        # Uniswap swap interface
└── libraries/
    ├── LeverageCalculator.sol      # Leverage math utilities - 183 lines
    └── HealthFactorLib.sol         # Health factor calculations - 200 lines

script/
├── DeployManager.s.sol             # Deploy callback contract
├── DeployReactive.s.sol            # Deploy reactive contract
├── DeployFunder.s.sol              # Deploy funder contract
├── DeployReactiveFunder.s.sol      # Deploy reactive funder
├── InitiateLoop.s.sol              # Start a loop
├── RequestUnwind.s.sol             # Request unwind
├── CheckPosition.s.sol             # View position status
└── EmergencyUnwind.s.sol           # Emergency unwind

test/
├── e2e/
│   ├── FullSystemE2E.t.sol         # Full system E2E tests (26 tests)
│   └── FunderIntegration.t.sol     # Funder integration tests (30 tests)
├── fork/
│   ├── AutoLooperFork.t.sol        # Fork tests against real Aave (15 tests)
│   ├── EnhancedCallbacksFork.t.sol # Enhanced callbacks fork tests (26 tests)
│   └── DiagnoseAave.t.sol          # Aave diagnostic tests (3 tests)
├── reactive/
│   ├── AutoLooperReactive.t.sol    # Reactive contract tests (19 tests)
│   └── AutoLooperReactiveEnhanced.t.sol # Enhanced RSC tests (23 tests)
├── fuzz/
│   ├── LeverageCalculator.fuzz.t.sol # Fuzz tests (21 tests)
│   └── HealthFactorLib.fuzz.t.sol    # Fuzz tests (21 tests)
├── unit/
│   ├── LeverageCalculator.t.sol    # Unit tests (13 tests)
│   ├── Funder.t.sol                # Funder unit tests (27 tests)
│   └── SubscriptionExpiryFinality.t.sol # Subscription tests (17 tests)
└── integration/
    └── LoopExecution.t.sol         # Integration tests (5 tests)

docs/
├── BOUNTY_COMPLIANCE.md            # Bounty requirements verification
├── BOUNTY_DEMO_STRATEGY.md         # Demo strategy for testnet limitations
├── DEMO_VIDEO_SCRIPT.md            # Video script (3-5 minutes)
├── ADVANCED_FEATURES.md            # Advanced features documentation
├── SECURITY_AUDIT.md               # Slither security analysis
├── ENHANCEMENT_BRAINSTORM.md       # Feature research from blog articles
└── GAS_OPTIMIZATION.md             # Gas optimization notes
```

---

## 🛡️ Security Features

1. **AbstractCallback Pattern** - Official Reactive Network authorization
2. **Dual Authorization** - Callback proxy + RVM ID validation
3. **Health Factor Guardian** - Automatic emergency unwind when HF < 1.1
4. **Circuit Breaker** - Pause on anomalous price movements (10% deviation)
5. **Slippage Protection** - Configurable tolerance (default 0.5%)
6. **Max Iterations Cap** - Prevents infinite loops (max 15)
7. **Rate Limiting** - Minimum blocks between callbacks
8. **Gas Budget Tracking** - Per-position gas spending limits
9. **Auto-Revoking Approvals** - Revokes token approvals after position close
10. **Emergency Withdraw** - User can always exit with `emergencyWithdraw()`

### Security Audit (Slither)

| Severity | Count | Status |
|----------|-------|--------|
| High | 2 | Reviewed - Mitigated by Design |
| Medium | 15 | Reviewed - Acceptable Risk |
| Low | 9 | Reviewed - Informational |

[📖 Full Security Analysis](docs/SECURITY_AUDIT.md)

---

## ⚡ Advanced Features

### Core Features

| Feature | Description | Status |
|---------|-------------|--------|
| **Flash Loan Mode** | Instant leverage in single tx (~85% gas savings) | ✅ |
| **Flash Unwind** | Instant position unwinding via flash loans | ✅ |
| **Same-Asset Loop** | Bypass DEX liquidity by borrowing same asset | ✅ |
| **Health Factor Guardian** | Auto-unwind when HF drops below threshold | ✅ |
| **Self-Sustaining Gas** | Reactivate pattern for RSC auto-funding | ✅ |

### Enhanced Features (AutoLooperReactiveEnhanced)

| Feature | Description | Status |
|---------|-------------|--------|
| **Take-Profit Triggers** | Automatic unwind at price target | ✅ |
| **Stop-Loss Triggers** | Automatic unwind below price floor | ✅ |
| **CRON Health Checks** | Periodic batch monitoring (~100 blocks) | ✅ |
| **Approval Magic** | One-click deposit via token approval | ✅ |
| **Liquidation Monitoring** | Track guardian failures for analytics | ✅ |
| **Finality-Aware Callbacks** | Wait for block finality before actions | ✅ |
| **Subscription Expiry** | Time-bounded automation subscriptions | ✅ |

### Safety Features (from Blog Article Analysis)

| Feature | Source | Status |
|---------|--------|--------|
| **Budget Caps** | AI Agents Article | ✅ |
| **TWAP Execution** | NewEra Article | ✅ |
| **MEV Protection** | NewEra Article | ✅ |
| **APY Monitoring** | Shogun Article | ✅ |
| **Multi-User Batching** | Aave Unified Article | ✅ |

[📖 Full Advanced Features Documentation](docs/ADVANCED_FEATURES.md)

---

## ✨ Bounty Requirements Checklist

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| Simple leveraged looping strategy | Supply→Borrow→Swap→Supply cycle + Flash loan option | ✅ |
| On existing lending protocol | Aave V3 (bolt-on, no modifications) | ✅ |
| Using Reactive Contracts | AutoLooperReactive with stateless design | ✅ |
| User opt-in mechanism | `deposit()` function initiates loop | ✅ |
| Automatic supply/borrow/swap steps | RSC triggers each step via callbacks | ✅ |
| Target leverage configuration | Configurable `targetLeverage` parameter | ✅ |
| Safe unwind capability | `requestUnwind()` + `executeUnwindStep()` | ✅ |
| Automation use case (not cross-chain) | Single-chain Sepolia focus | ✅ |

### Key Differentiators (from IMPLEMENTATION_PLAN.md)

| Differentiator | Status |
|----------------|--------|
| Flash Loan Instant Leverage | ✅ |
| Self-Sustaining Gas (Reactivate) | ✅ |
| Health Factor Guardian | ✅ |
| Stateless RSC Architecture | ✅ |
| Dual-Mode Operation (Iterative + Flash) | ✅ |

---

## 📊 Test Results

```
252 passing

Test Suites:
  ✓ FullSystemE2ETest (26 tests)         - Full E2E automation tests
  ✓ FunderIntegrationTest (30 tests)     - Reactivate pattern tests
  ✓ AutoLooperForkTest (15 tests)        - Fork tests against real Aave
  ✓ EnhancedCallbacksForkTest (26 tests) - Enhanced features fork tests
  ✓ AutoLooperReactiveEnhancedTest (23 tests) - Enhanced RSC tests
  ✓ AutoLooperReactiveTest (19 tests)    - Basic RSC tests
  ✓ LeverageCalculatorFuzzTest (21 tests) - Fuzz testing leverage math
  ✓ HealthFactorLibFuzzTest (21 tests)   - Fuzz testing health factor
  ✓ FunderTest (27 tests)                - Funder unit tests
  ✓ SubscriptionExpiryFinalityTest (17 tests) - Subscription expiry tests
  ✓ LeverageCalculatorTest (13 tests)    - Leverage calculator unit tests
  ✓ HealthFactorLibTest (6 tests)        - Health factor unit tests
  ✓ LoopExecutionTest (5 tests)          - Loop execution integration
  ✓ DiagnoseAaveTest (3 tests)           - Aave diagnostic tests
```

---

## 🤔 Why Reactive Network?

### The Problem

Traditional leveraged looping requires:
- **10+ manual transactions** for 3x leverage
- **Constant monitoring** of health factor
- **Manual intervention** for unwinding
- **Risk of liquidation** if not watching

### The Reactive Solution

Reactive Network enables **autonomous, trustless automation**:

| Without Reactive | With Reactive |
|------------------|---------------|
| 10+ manual transactions | Single deposit → fully automated |
| Manual health monitoring | Continuous RSC monitoring (every event) |
| Manual emergency unwind | Automatic emergency unwind when HF < 1.1 |
| User must stay online | Runs 24/7 autonomously |
| Gas paid per transaction | Self-sustaining gas via Reactivate |

### Key Quote from Reactive Blog:

> "Inversion of Control allows us to avoid hosting additional entities that emulate humans signing transactions. If you have a predefined scenario outlining the sequence of transactions following on-chain events, you should be able to run this logic in a completely decentralized manner."

**Auto-Looper is the perfect embodiment of this principle.**

---

## 📞 Links

- **Telegram Bot:** [@reactive_auto_looper_bot](https://t.me/reactive_auto_looper_bot)
- **Reactive Network Docs:** [https://dev.reactive.network/](https://dev.reactive.network/)
- **ReactScan Explorer:** [https://reactscan.net/](https://reactscan.net/)
- **Sepolia Explorer:** [https://sepolia.etherscan.io/](https://sepolia.etherscan.io/)
- **Aave V3 Docs:** [https://docs.aave.com/](https://docs.aave.com/)
- **Bounty Spec:** [Reactive Bounties: Second Bounty & Timeline](https://blog.reactive.network/reactive-bounties-second-bounty-timeline/)

### Contract Links

| Contract | Network | Address |
|----------|---------|---------|
| AutoLooperManager | Sepolia | [`0x188c7b7dC3EEbCA58371abC8D62cB62bEE201d47`](https://sepolia.etherscan.io/address/0x188c7b7dC3EEbCA58371abC8D62cB62bEE201d47) |
| AutoLooperReactive | Lasna | [`0xE58eA8c7eC0E47D195f720f34b3187F59eb27894`](https://lasna.reactscan.net/address/0xE58eA8c7eC0E47D195f720f34b3187F59eb27894) |
| Funder | Sepolia | [`0x9bcbE702215763e2D90BE8f3a374a41a32a0b791`](https://sepolia.etherscan.io/address/0x9bcbE702215763e2D90BE8f3a374a41a32a0b791) |

---

## 📄 License

MIT

---

## 🙏 Acknowledgments

- [Reactive Network](https://reactive.network) - Event-driven blockchain infrastructure
- [Aave](https://aave.com) - Decentralized lending protocol
- [Foundry](https://getfoundry.sh) - Smart contract development framework
- [OpenZeppelin](https://openzeppelin.com) - Security libraries

---

**Bounty Submission - December 2025**
