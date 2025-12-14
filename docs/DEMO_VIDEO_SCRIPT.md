# Auto-Looper Demo Video Script

## Video Overview
**Duration:** 3-5 minutes  
**Title:** "Auto-Looper: Automated Leveraged Looping with Reactive Smart Contracts"

---

## Scene 1: Introduction (30 seconds)

### Narration
> "Auto-Looper is an automated leveraged looping system built on Reactive Network. It allows DeFi users to achieve target leverage on Aave V3 through automated supply-borrow-swap cycles, with continuous health factor monitoring to prevent liquidation."

### Visuals
- Show high-level architecture diagram
- Highlight: Sepolia (Manager) ↔ Reactive Network (Monitor) flow

---

## Scene 2: Problem Statement (30 seconds)

### Narration
> "Traditional leveraged looping requires multiple manual transactions and constant monitoring. If health factor drops, you risk liquidation. Auto-Looper solves this by:
> 1. Automating the looping process
> 2. Continuously monitoring health factors
> 3. Automatically unwinding positions when needed"

### Visuals
- Animation showing manual looping pain points
- Health factor gauge dropping dangerously

---

## Scene 3: Architecture Overview (45 seconds)

### Narration
> "The system consists of four contracts:
> - **AutoLooperManager** on Sepolia handles all Aave interactions
> - **AutoLooperReactive** on Reactive Network monitors events and triggers callbacks
> - **Funder** collects fees for gas sustainability  
> - **ReactiveFunderRC** automatically tops up the reactive contract"

### Visuals
- Animated diagram showing contract interactions
- Highlight the callback flow from Reactive → Sepolia

---

## Scene 4: Live Demo - Deposit & Loop (90 seconds)

### Terminal Commands
```bash
# Check initial state
cast call $MANAGER "hasPosition(address)" $USER --rpc-url $SEPOLIA_RPC

# Deposit WETH to start looping (3x leverage)
cast send $MANAGER "deposit(address,address,uint256,uint256,uint256,bool)" \
  $WETH $USDC 1000000000000000000 3000000000000000000 10 false \
  --value 0.01ether --rpc-url $SEPOLIA_RPC --private-key $USER_KEY

# Check position created
cast call $MANAGER "getPosition(address)" $USER --rpc-url $SEPOLIA_RPC
```

### Narration
> "Let's deposit 1 WETH with a target of 3x leverage. The system immediately supplies to Aave and emits a PositionUpdated event."

### Visuals
- Terminal showing commands executing
- Reactscan showing the reactive contract detecting the event

---

## Scene 5: Reactive Automation (45 seconds)

### Narration
> "Watch the Reactive Network in action. When AutoLooperReactive detects the deposit event, it automatically calls executeLoopStep() on the Manager. Each iteration:
> 1. Borrows against collateral
> 2. Swaps borrowed USDC for WETH  
> 3. Supplies WETH back to Aave
> 4. Checks health factor
> 5. Continues until target reached"

### Visuals
- Reactscan transaction log showing callbacks
- Health factor increasing with each loop
- Leverage approaching target (3x)

---

## Scene 6: Health Factor Protection (30 seconds)

### Narration
> "If health factor drops below the minimum threshold (1.1), the system automatically switches to emergency unwind mode, protecting your position from liquidation."

### Visuals
- Show code snippet of health factor check
- Animation of auto-unwind triggering

---

## Scene 7: Test Results (30 seconds)

### Narration
> "Auto-Looper has been thoroughly tested with:
> - 120 passing tests
> - Fork tests against real Aave V3
> - Fuzz tests for edge cases
> - Full E2E verification on testnets"

### Visuals
- `forge test` output showing all tests passing
- Test coverage breakdown

---

## Scene 8: Conclusion (30 seconds)

### Narration
> "Auto-Looper demonstrates the power of Reactive Smart Contracts for DeFi automation. No more manual looping, no more missed liquidations. Just set your target leverage and let the system work."

### Call to Action
> "Check out the code on GitHub and try it on Sepolia testnet!"

### Visuals
- Deployed contract addresses
- GitHub link
- QR code to documentation

---

## Technical Details to Show

### Deployed Contracts
| Contract | Network | Address |
|----------|---------|---------|
| AutoLooperManager | Sepolia | `0x32bD92BdDB604b3BbFEE9B3042d38CF2B6e7e49f` |
| AutoLooperReactive | Lasna | `0x5B8fEc5DBBE29d0B52141e51d407aDf8035bac3A` |
| Funder | Sepolia | `0x9bcbE702215763e2D90BE8f3a374a41a32a0b791` |
| ReactiveFunderRC | Lasna | `0xa8D3bC8A55Cf854b3184C6bEaF09aE795De02ADC` |

### Key Transactions to Highlight
1. Deposit transaction on Sepolia
2. Reactive detection on Reactscan
3. Callback execution on Sepolia
4. Loop completion event

---

## Recording Checklist

- [ ] Clean terminal with large font
- [ ] Reactscan tab open
- [ ] Etherscan Sepolia tab open
- [ ] Test wallets funded
- [ ] Environment variables set
- [ ] Screen recording software ready
- [ ] Microphone tested

---

## Backup Plan

If live demo fails:
1. Show pre-recorded transaction hashes
2. Walk through Etherscan/Reactscan links
3. Show test output as proof of functionality

### Pre-recorded Transaction Links
- Deposit: `https://sepolia.etherscan.io/tx/0x...`
- Loop Step 1: `https://sepolia.etherscan.io/tx/0x...`
- Reactive Callback: `https://reactscan.net/tx/0x...`
