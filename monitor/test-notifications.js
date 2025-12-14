#!/usr/bin/env node

/**
 * Test Telegram Integration with E2E Notifications
 */

import { sendTelegramMessage, Notifications } from './telegram-bot.js';

async function testNotifications() {
    console.log('Testing E2E Telegram integration...\n');

    // Test E2E Started notification
    const r1 = await sendTelegramMessage(Notifications.e2eTestStarted());
    console.log(r1?.ok ? '✅ E2E Started notification sent' : '❌ Failed');

    // Simulate system status
    const status = {
        manager: { deployed: true },
        reactive: { deployed: true },
        reserves: { amount: '0.2', ok: true },
        subscription: { active: true }
    };
    const r2 = await sendTelegramMessage(Notifications.systemStatus(status));
    console.log(r2?.ok ? '✅ System status notification sent' : '❌ Failed');

    // Test position update notification
    const positionData = {
        user: '0x3a949910627c3D424d0871EFa2A34214293A5E25',
        currentLeverage: '2500000000000000000', // 2.5x
        targetLeverage: '3000000000000000000',  // 3x
        healthFactor: '1800000000000000000',     // 1.8
        iteration: '3',
        state: 1 // LOOPING
    };
    const r3 = await sendTelegramMessage(Notifications.positionUpdated(positionData, '0xabc123...'));
    console.log(r3?.ok ? '✅ Position update notification sent' : '❌ Failed');

    // Test result notification
    const r4 = await sendTelegramMessage(Notifications.e2eTestResult(true, [
        'Prerequisites verified',
        'Manager deployed ✓',
        'Reactive deployed ✓',
        'Subscription active ✓',
        'System ready for automation'
    ]));
    console.log(r4?.ok ? '✅ E2E Result notification sent' : '❌ Failed');

    console.log('\n🎉 All Telegram notifications test complete!');
}

testNotifications().catch(console.error);
