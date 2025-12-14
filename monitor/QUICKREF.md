# 🚀 Telegram Bot Quick Reference

## One-Line Commands

```bash
# Start bot
node monitor/telegram-bot-enhanced.js

# Run tests
node monitor/telegram-bot-test.js smoke                                    # Quick test (15s)
node monitor/telegram-bot-test.js all                                      # Full test (90s)

# Verify address
node monitor/verify-live-address.js 0x742D35Cc6634C0532925a3b844bc9e7595F89999

# Check if bot is running
ps aux | grep telegram-bot
```

## Essential Bot Commands

```
/start          - Initialize bot
/help           - Show all commands
/status         - System health
/position <addr> - View position
/hf <addr>      - Health factor
/leverage <addr> - Current leverage
/reserves       - Callback reserves
/rvmstatus      - RVM status
```

## Test Address (Has Position Data)
```
0x742D35Cc6634C0532925a3b844bc9e7595F89999

Note: hasPosition() returns false (IDLE state)
But: /hf and /leverage work! (HF: 1.0389, Leverage: 4.86x)
```

## Quick Fixes

### "Unknown command"
```bash
# Check command in help
/help

# Verify bot logs
tail -f bot.log
```

### "Bad address checksum"
```bash
# Get checksummed address
node -e "import('ethers').then(({ethers}) => console.log(ethers.getAddress('0xlowercase')))"
```

### Command not working
```bash
# Test it
node monitor/telegram-bot-test.js "/command args"

# Verify address first
node monitor/verify-live-address.js 0xAddress
```

## File Locations

```
monitor/
├── telegram-bot-enhanced.js  # Main bot (1380 lines)
├── telegram-bot-test.js      # Test framework (500 lines)
├── verify-live-address.js    # Address verifier (250 lines)
├── TESTING.md                # Testing guide (400 lines)
├── DEBUG.md                  # Debug guide (350 lines)
└── SUMMARY.md                # Complete summary (300 lines)

docs/
└── TELEGRAM_BOT.md           # User documentation (344 lines)
```

## Status

✅ Bot: Running  
✅ Commands: 18+ working  
✅ Tests: 30+ passing  
✅ Documentation: Complete  
✅ Ready: Production  

## Support

Problems? Check in order:
1. DEBUG.md - Troubleshooting guide
2. TESTING.md - Test framework docs
3. SUMMARY.md - Complete overview
4. Telegram Bot docs - User guide

---

**Bot Username:** [@reactive_auto_looper_bot](https://t.me/reactive_auto_looper_bot)  
**Status:** 🟢 Online  
**Version:** v2.0 Enhanced
