# 🧪 Telegram Bot Testing Framework

Comprehensive testing suite for validating all Telegram bot commands, error handling, and integration with live contracts.

## 📁 Test Files

### 1. **telegram-bot-test.js** - Main Test Suite
Automated testing framework that validates all bot commands systematically.

**Features:**
- ✅ 30+ test cases covering all commands
- ✅ Categorized tests (Basic, Position, Advanced, Reactive, Monitoring, Info, Error Handling)
- ✅ Critical vs non-critical test classification
- ✅ Detailed pass/fail reporting with error messages
- ✅ Multiple test modes (all, smoke, position, interactive)

**Usage:**
```bash
# Run all tests (comprehensive)
node telegram-bot-test.js all

# Quick smoke test (7 essential commands)
node telegram-bot-test.js smoke

# Test all position commands with live address
node telegram-bot-test.js position

# Interactive test mode
node telegram-bot-test.js interactive

# Test single command
node telegram-bot-test.js "/status"
```

### 2. **verify-live-address.js** - Address Verification Tool
Validates that a given address has an active position and all contract calls work correctly.

**Features:**
- ✅ Address format validation
- ✅ Position existence check
- ✅ Full position details extraction
- ✅ Health factor verification
- ✅ Current leverage check
- ✅ Detailed error reporting

**Usage:**
```bash
# Verify specific address
node verify-live-address.js 0x742D35Cc6634C0532925a3b844bc9e7595F89999

# Verify default test address
node verify-live-address.js
```

**Sample Output:**
```
╔════════════════════════════════════════════════════════════════╗
║              LIVE ADDRESS VERIFICATION TOOL                     ║
╚════════════════════════════════════════════════════════════════╝

Address: 0x742D35Cc6634C0532925a3b844bc9e7595F89999

1. Validating address format...
   ✅ Valid Ethereum address

2. Checking position status...
   ✅ Position exists

3. Fetching position details...
   Position Data:
   ├─ State: 1 (LOOPING)
   ├─ Collateral Asset: 0x7b79...
   ├─ Current Leverage: 2.85x
   ├─ Target Leverage: 3.00x
   └─ Health Factor: 1.75

4. Checking health factor...
   Health Factor: 1.7500 💛 Caution

5. Getting current leverage...
   Current Leverage: 2.85x

════════════════════════════════════════════════════════════
VERIFICATION SUMMARY
════════════════════════════════════════════════════════════
Address Valid: ✅
Has Position: ✅
Contract Calls: ✅ All working

✅ ADDRESS IS SUITABLE FOR TESTING!
```

---

## 🧪 Test Categories

### 1. Basic Commands (6 tests)
- `/start` - Welcome message
- `/help` - Command reference
- `/status` - System status
- `/health` - Health check
- `/contracts` - Contract addresses
- `/networks` - Network info

### 2. Position Commands (8 tests)
- `/position <addr>` - Full position details
- `/position` - Missing address error
- `/position <invalid>` - Invalid address error
- `/leverage <addr>` - Leverage check
- `/hf <addr>` - Health factor
- `/collateral <addr>` - Collateral info
- `/debt <addr>` - Debt details
- `/myposition` - User position

### 3. Advanced Commands (4 tests)
- `/tp <addr>` - Take-profit/stop-loss config
- `/fees` - Fee structure
- `/settings` - System settings
- `/features` - Feature list

### 4. Reactive Network Commands (5 tests)
- `/reserves` - Callback reserves
- `/subscription` - RVM subscriptions
- `/rvmstatus` - Full RVM status
- `/rvmdebt` - RVM debt check
- `/reactive` - Reactive contract info

### 5. Monitoring Commands (5 tests)
- `/watch <addr>` - Add to watchlist
- `/watchlist` - View watchlist
- `/unwatch <addr>` - Remove from watchlist
- `/setmy <addr>` - Set user address
- `/myposition` - After setting address

### 6. Info Commands (2 tests)
- `/features` - Feature overview
- `/stats` - System statistics

### 7. Error Handling (2 tests)
- Unknown commands
- Commands with extra spaces

---

## 📊 Test Results Interpretation

### ✅ Success Criteria
- **Critical Tests Pass Rate:** 100%
- **Overall Pass Rate:** ≥ 95%
- **No contract call errors**
- **All commands respond within 3 seconds**

### ❌ Failure Indicators
- RPC connection errors
- Contract deployment issues
- Invalid bot token/chat ID
- Missing dependencies

### 📈 Performance Metrics
- **Command Response Time:** < 2s average
- **Event Listener Setup:** < 5s
- **Bot Startup Time:** < 3s

---

## 🔍 Debugging Failed Tests

### Common Issues

#### 1. "Unknown command" responses
**Cause:** Command not registered in `commands` object
**Fix:** Add command handler in `telegram-bot-enhanced.js`

#### 2. RPC connection errors
**Cause:** RPC endpoint down or rate limited
**Fix:** Update `SEPOLIA_RPC_URL` or `REACTIVE_RPC_URL` in `.env`

#### 3. Contract call failures
**Cause:** Wrong ABI or contract address
**Fix:** Verify addresses in `config.js` and ABIs in bot file

#### 4. Bot token/chat ID errors
**Cause:** Invalid credentials
**Fix:** Update `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in `.env`

#### 5. Address validation failures
**Cause:** Incorrect checksum
**Fix:** Use checksummed address from `ethers.getAddress()`

---

## 🚀 Running Tests

### Prerequisites
```bash
# Install dependencies
npm install

# Set environment variables
export TELEGRAM_BOT_TOKEN=your_token
export TELEGRAM_CHAT_ID=your_chat_id
export SEPOLIA_RPC_URL=your_sepolia_rpc
export REACTIVE_RPC_URL=https://lasna-rpc.rnk.dev/
```

### Test Execution

#### Full Test Suite
```bash
node telegram-bot-test.js all
```
**Time:** ~90 seconds  
**Tests:** 30+ commands  
**Best for:** Pre-deployment validation

#### Smoke Test
```bash
node telegram-bot-test.js smoke
```
**Time:** ~15 seconds  
**Tests:** 7 critical commands  
**Best for:** Quick health check

#### Position Commands Test
```bash
node telegram-bot-test.js position
```
**Time:** ~20 seconds  
**Tests:** All position-related commands  
**Best for:** After contract changes

#### Address Verification
```bash
node verify-live-address.js 0xYourAddress
```
**Time:** ~5 seconds  
**Tests:** Position validity  
**Best for:** Finding test addresses

---

## 📝 Test Configuration

### Test Addresses
```javascript
const TEST_ADDRESSES = {
    withPosition: '0x742D35Cc6634C0532925a3b844bc9e7595F89999', // Has active position
    noPosition: '0x0000000000000000000000000000000000000001', // No position
    invalid: '0xinvalid', // Invalid format
};
```

### Test Delays
- **Between tests:** 1.5s (prevents rate limiting)
- **Response wait:** 2s (allows bot to process)
- **Bot startup:** 3s (initialization time)

---

## 📤 Continuous Integration

### GitHub Actions Example
```yaml
name: Telegram Bot Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '20'
      
      - name: Install dependencies
        run: npm install
      
      - name: Run smoke test
        env:
          TELEGRAM_BOT_TOKEN: ${{ secrets.TELEGRAM_BOT_TOKEN }}
          TELEGRAM_CHAT_ID: ${{ secrets.TELEGRAM_CHAT_ID }}
          SEPOLIA_RPC_URL: ${{ secrets.SEPOLIA_RPC_URL }}
        run: node monitor/telegram-bot-test.js smoke
      
      - name: Verify address
        run: node monitor/verify-live-address.js
```

---

## 🐛 Known Issues & Workarounds

### Issue 1: "bad address checksum"
**Problem:** Ethers.js v6 requires checksummed addresses  
**Solution:** Use `ethers.getAddress()` or lowercase all addresses

### Issue 2: Position decoding errors
**Problem:** Empty position returns 0x000... which fails ABI decoding  
**Solution:** Check `hasPosition()` first before `getPosition()`

### Issue 3: RVM debt false positives
**Problem:** RVM debt check may fail if system contract not accessible  
**Solution:** Wrap in try-catch, show "Check failed" instead of error

### Issue 4: Event listener memory leaks
**Problem:** Long-running bot may accumulate event listeners  
**Solution:** Use `removeAllListeners()` before re-registering

---

## 🎯 Best Practices

### 1. Test Isolation
- Each test should be independent
- Clean up watchlist/state between tests
- Use separate chat IDs for testing vs production

### 2. Rate Limiting
- Add delays between commands (1-2s)
- Use exponential backoff for retries
- Respect Telegram's 30 requests/second limit

### 3. Error Handling
- Always wrap contract calls in try-catch
- Provide user-friendly error messages
- Log errors for debugging

### 4. Test Data
- Use real testnet addresses when possible
- Create test fixtures for edge cases
- Document expected vs actual responses

### 5. Continuous Testing
- Run smoke test on every commit
- Full test suite before releases
- Monitor production bot logs

---

## 📚 Additional Resources

- [Telegram Bot API Documentation](https://core.telegram.org/bots/api)
- [Ethers.js v6 Documentation](https://docs.ethers.org/v6/)
- [Reactive Network Documentation](https://rnk.dev)
- [Main Bot Documentation](../docs/TELEGRAM_BOT.md)

---

## 🤝 Contributing

To add new tests:

1. Add test case to `testCases` array in `telegram-bot-test.js`
2. Specify category, name, command, expected response
3. Mark as critical if essential functionality
4. Run full test suite to verify
5. Update this README with new test category

Example:
```javascript
{
    category: 'New Category',
    name: '/newcommand - Description',
    command: '/newcommand',
    expectedInResponse: ['Expected', 'Text'],
    critical: true
}
```

---

## 📞 Support

For issues with the testing framework:
- Check bot logs in terminal
- Verify environment variables
- Run `verify-live-address.js` first
- Test with `/start` and `/help` commands

Bot working but tests failing? The bot is the source of truth!
