require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const TelegramBot = require('node-telegram-bot-api');

const token = process.env.TELEGRAM_BOT_TOKEN;
const chatId = process.env.TELEGRAM_CHAT_ID;

if (!token || !chatId) {
  console.error('Error: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID must be set in .env');
  process.exit(1);
}

const bot = new TelegramBot(token, { polling: false });

const msg = `🎉 REACTIVE AUTOMATION WORKING

✅ RVM is processing events
✅ Callbacks executing successfully  
✅ Position unwinding in progress

Current Status:
• State: UNWINDING
• Leverage: ~4.85x
• Target: 1.0x
• Iterations: 5+

Bug Found and Fixed:
• Reactive contract had outstanding debt
• Funded contract and cleared debt
• Re-subscribed to events
• Now processing callbacks correctly`;

bot.sendMessage(chatId, msg)
  .then(() => console.log('Telegram notification sent!'))
  .catch(err => console.error('Error:', err.message));
