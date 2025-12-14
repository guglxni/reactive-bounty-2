#!/usr/bin/env node

/**
 * Test Telegram Bot Connection
 */

import dotenv from 'dotenv';
dotenv.config({ path: '../.env' });

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const TELEGRAM_CHAT_ID = process.env.TELEGRAM_CHAT_ID;

if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) {
    console.error('❌ Missing: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID');
    process.exit(1);
}

async function test() {
    console.log('Testing Telegram bot...');
    
    // First get bot info
    const infoResp = await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe`);
    const info = await infoResp.json();
    console.log('Bot Info:', JSON.stringify(info, null, 2));
    
    if (!info.ok) {
        console.error('Failed to get bot info:', info.description);
        process.exit(1);
    }
    
    console.log(`\nConnected as @${info.result.username}`);
    
    // Then send a test message
    const testMessage = `🧪 <b>Reactive Auto-Looper Bot Test</b>

✅ Telegram integration working!
📡 Ready to monitor events on:
• Sepolia (Origin/Destination)
• Lasna (Reactive Network)

<i>This is an automated test message.</i>`;

    const msgResp = await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            chat_id: TELEGRAM_CHAT_ID,
            text: testMessage,
            parse_mode: 'HTML'
        })
    });
    
    const msg = await msgResp.json();
    
    if (msg.ok) {
        console.log('\n✅ Test message sent successfully!');
        console.log(`Message ID: ${msg.result.message_id}`);
    } else {
        console.error('\n❌ Failed to send message:', msg.description);
    }
}

test().catch(console.error);
