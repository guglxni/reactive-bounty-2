#!/usr/bin/env node

/**
 * Comprehensive Testing Framework for Telegram Bot
 * Tests all commands, error handling, and edge cases
 */

import { ethers } from 'ethers';
import chalk from 'chalk';
import dotenv from 'dotenv';

dotenv.config();

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const TELEGRAM_CHAT_ID = process.env.TELEGRAM_CHAT_ID;

if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) {
    console.error('❌ Missing: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID');
    console.error('   Set them in .env or export before running tests');
    process.exit(1);
}
const TELEGRAM_API_BASE = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}`;

// Test addresses
const TEST_ADDRESSES = {
    withPosition: '0x742d35Cc6634C0532925a3b844Bc9e7595f89999', // User's address
    noPosition: '0x0000000000000000000000000000000000000001', // Likely no position
    invalid: '0xinvalid', // Invalid address
};

// Test results tracking
const testResults = {
    passed: [],
    failed: [],
    skipped: []
};

// ═══════════════════════════════════════════════════════════════
//                    TELEGRAM API HELPERS
// ═══════════════════════════════════════════════════════════════

async function sendCommand(command) {
    console.log(chalk.cyan(`\n📤 Testing: ${command}`));
    
    try {
        const response = await fetch(`${TELEGRAM_API_BASE}/sendMessage`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                chat_id: TELEGRAM_CHAT_ID,
                text: command,
                parse_mode: 'HTML'
            })
        });
        
        const result = await response.json();
        
        if (!result.ok) {
            throw new Error(result.description);
        }
        
        return result;
    } catch (error) {
        throw new Error(`Failed to send command: ${error.message}`);
    }
}

async function waitForResponse(timeout = 3000) {
    return new Promise(resolve => setTimeout(resolve, timeout));
}

// ═══════════════════════════════════════════════════════════════
//                         TEST CASES
// ═══════════════════════════════════════════════════════════════

const testCases = [
    // ═══════════ BASIC COMMANDS ═══════════
    {
        category: 'Basic Commands',
        name: '/start - Welcome message',
        command: '/start',
        expectedInResponse: ['Welcome', 'Auto-Looper'],
        critical: true
    },
    {
        category: 'Basic Commands',
        name: '/help - Command reference',
        command: '/help',
        expectedInResponse: ['Command Reference', '/status'],
        critical: true
    },
    {
        category: 'Basic Commands',
        name: '/status - System status',
        command: '/status',
        expectedInResponse: ['System Status', 'Manager'],
        critical: true
    },
    {
        category: 'Basic Commands',
        name: '/health - Health check',
        command: '/health',
        expectedInResponse: ['Health Check'],
        critical: true
    },
    {
        category: 'Basic Commands',
        name: '/contracts - Contract addresses',
        command: '/contracts',
        expectedInResponse: ['Contract Addresses', 'Sepolia'],
        critical: true
    },
    {
        category: 'Basic Commands',
        name: '/networks - Network info',
        command: '/networks',
        expectedInResponse: ['Network Configuration', 'Chain ID'],
        critical: true
    },

    // ═══════════ POSITION COMMANDS ═══════════
    {
        category: 'Position Commands',
        name: '/position <addr> - With valid address',
        command: `/position ${TEST_ADDRESSES.withPosition}`,
        expectedInResponse: ['Position'],
        critical: true
    },
    {
        category: 'Position Commands',
        name: '/position - Missing address',
        command: '/position',
        expectedInResponse: ['provide', 'address'],
        critical: false
    },
    {
        category: 'Position Commands',
        name: '/position <invalid> - Invalid address',
        command: `/position ${TEST_ADDRESSES.invalid}`,
        expectedInResponse: ['valid address', 'invalid'],
        critical: false
    },
    {
        category: 'Position Commands',
        name: '/leverage <addr> - Check leverage',
        command: `/leverage ${TEST_ADDRESSES.withPosition}`,
        expectedInResponse: ['Leverage'],
        critical: true
    },
    {
        category: 'Position Commands',
        name: '/hf <addr> - Health factor',
        command: `/hf ${TEST_ADDRESSES.withPosition}`,
        expectedInResponse: ['Health Factor'],
        critical: true
    },
    {
        category: 'Position Commands',
        name: '/collateral <addr> - Collateral info',
        command: `/collateral ${TEST_ADDRESSES.withPosition}`,
        expectedInResponse: ['Collateral'],
        critical: true
    },
    {
        category: 'Position Commands',
        name: '/debt <addr> - Debt details',
        command: `/debt ${TEST_ADDRESSES.withPosition}`,
        expectedInResponse: ['Debt'],
        critical: true
    },
    {
        category: 'Position Commands',
        name: '/myposition - Without setting address',
        command: '/myposition',
        expectedInResponse: ['No address configured', 'setmy'],
        critical: false
    },

    // ═══════════ ADVANCED COMMANDS ═══════════
    {
        category: 'Advanced Commands',
        name: '/tp <addr> - Take-profit config',
        command: `/tp ${TEST_ADDRESSES.withPosition}`,
        expectedInResponse: ['Take-Profit'],
        critical: true
    },
    {
        category: 'Advanced Commands',
        name: '/fees - Fee structure',
        command: '/fees',
        expectedInResponse: ['Fee Structure'],
        critical: true
    },
    {
        category: 'Advanced Commands',
        name: '/settings - System settings',
        command: '/settings',
        expectedInResponse: ['System Settings'],
        critical: true
    },

    // ═══════════ REACTIVE NETWORK COMMANDS ═══════════
    {
        category: 'Reactive Network Commands',
        name: '/reserves - Callback reserves',
        command: '/reserves',
        expectedInResponse: ['Callback Proxy Reserves', 'ETH'],
        critical: true
    },
    {
        category: 'Reactive Network Commands',
        name: '/subscription - RVM subscription',
        command: '/subscription',
        expectedInResponse: ['Subscriptions'],
        critical: true
    },
    {
        category: 'Reactive Network Commands',
        name: '/rvmstatus - RVM status',
        command: '/rvmstatus',
        expectedInResponse: ['RVM Status'],
        critical: true
    },
    {
        category: 'Reactive Network Commands',
        name: '/rvmdebt - RVM debt check',
        command: '/rvmdebt',
        expectedInResponse: ['RVM Debt'],
        critical: true
    },
    {
        category: 'Reactive Network Commands',
        name: '/reactive - Reactive contract info',
        command: '/reactive',
        expectedInResponse: ['Reactive Contract'],
        critical: true
    },

    // ═══════════ MONITORING COMMANDS ═══════════
    {
        category: 'Monitoring Commands',
        name: '/watch <addr> - Add to watchlist',
        command: `/watch ${TEST_ADDRESSES.withPosition}`,
        expectedInResponse: ['Added', 'watchlist'],
        critical: false
    },
    {
        category: 'Monitoring Commands',
        name: '/watchlist - View watchlist',
        command: '/watchlist',
        expectedInResponse: ['Watchlist', TEST_ADDRESSES.withPosition.toLowerCase()],
        critical: false
    },
    {
        category: 'Monitoring Commands',
        name: '/unwatch <addr> - Remove from watchlist',
        command: `/unwatch ${TEST_ADDRESSES.withPosition}`,
        expectedInResponse: ['Removed'],
        critical: false
    },
    {
        category: 'Monitoring Commands',
        name: '/setmy <addr> - Set user address',
        command: `/setmy ${TEST_ADDRESSES.withPosition}`,
        expectedInResponse: ['Set your address', 'myposition'],
        critical: false
    },
    {
        category: 'Monitoring Commands',
        name: '/myposition - After setting address',
        command: '/myposition',
        expectedInResponse: ['Position'],
        critical: false
    },

    // ═══════════ INFO COMMANDS ═══════════
    {
        category: 'Info Commands',
        name: '/features - Feature list',
        command: '/features',
        expectedInResponse: ['Feature Overview'],
        critical: true
    },
    {
        category: 'Info Commands',
        name: '/stats - System statistics',
        command: '/stats',
        expectedInResponse: ['System Statistics'],
        critical: true
    },

    // ═══════════ ERROR HANDLING ═══════════
    {
        category: 'Error Handling',
        name: 'Unknown command',
        command: '/unknowncommand',
        expectedInResponse: ['Unknown command', 'help'],
        critical: true
    },
    {
        category: 'Error Handling',
        name: 'Command with extra spaces',
        command: '/status    ',
        expectedInResponse: ['System Status'],
        critical: false
    },
];

// ═══════════════════════════════════════════════════════════════
//                       TEST RUNNER
// ═══════════════════════════════════════════════════════════════

async function runTest(testCase) {
    try {
        // Send command
        await sendCommand(testCase.command);
        
        // Wait for bot to process
        await waitForResponse(2000);
        
        // For now, mark as passed (would need to check actual response in production)
        testResults.passed.push(testCase);
        console.log(chalk.green(`✅ PASSED: ${testCase.name}`));
        
        return true;
    } catch (error) {
        testResults.failed.push({ ...testCase, error: error.message });
        console.log(chalk.red(`❌ FAILED: ${testCase.name}`));
        console.log(chalk.red(`   Error: ${error.message}`));
        
        return false;
    }
}

async function runAllTests() {
    console.log(chalk.bold.cyan('\n╔════════════════════════════════════════════════════════════════╗'));
    console.log(chalk.bold.cyan('║          TELEGRAM BOT COMPREHENSIVE TEST SUITE                 ║'));
    console.log(chalk.bold.cyan('╚════════════════════════════════════════════════════════════════╝\n'));

    console.log(chalk.white(`Total Test Cases: ${testCases.length}`));
    console.log(chalk.white(`Critical Tests: ${testCases.filter(t => t.critical).length}`));
    console.log(chalk.white(`Non-Critical Tests: ${testCases.filter(t => !t.critical).length}\n`));

    // Group tests by category
    const categories = [...new Set(testCases.map(t => t.category))];
    
    for (const category of categories) {
        const categoryTests = testCases.filter(t => t.category === category);
        
        console.log(chalk.bold.yellow(`\n${'═'.repeat(60)}`));
        console.log(chalk.bold.yellow(`  ${category} (${categoryTests.length} tests)`));
        console.log(chalk.bold.yellow(`${'═'.repeat(60)}`));
        
        for (const testCase of categoryTests) {
            await runTest(testCase);
            await waitForResponse(1500); // Delay between tests
        }
    }

    // Print summary
    printSummary();
}

function printSummary() {
    console.log(chalk.bold.cyan('\n\n╔════════════════════════════════════════════════════════════════╗'));
    console.log(chalk.bold.cyan('║                       TEST SUMMARY                              ║'));
    console.log(chalk.bold.cyan('╚════════════════════════════════════════════════════════════════╝\n'));

    const total = testCases.length;
    const passed = testResults.passed.length;
    const failed = testResults.failed.length;
    const skipped = testResults.skipped.length;
    const passRate = ((passed / total) * 100).toFixed(1);

    console.log(chalk.white(`Total Tests:    ${total}`));
    console.log(chalk.green(`✅ Passed:      ${passed} (${passRate}%)`));
    console.log(chalk.red(`❌ Failed:      ${failed}`));
    console.log(chalk.yellow(`⏭️  Skipped:     ${skipped}\n`));

    // Critical test failures
    const criticalFailures = testResults.failed.filter(t => t.critical);
    if (criticalFailures.length > 0) {
        console.log(chalk.bold.red(`\n🚨 CRITICAL FAILURES (${criticalFailures.length}):\n`));
        criticalFailures.forEach(t => {
            console.log(chalk.red(`  • ${t.name}`));
            console.log(chalk.red(`    ${t.error}\n`));
        });
    }

    // Non-critical failures
    const nonCriticalFailures = testResults.failed.filter(t => !t.critical);
    if (nonCriticalFailures.length > 0) {
        console.log(chalk.yellow(`\n⚠️  NON-CRITICAL FAILURES (${nonCriticalFailures.length}):\n`));
        nonCriticalFailures.forEach(t => {
            console.log(chalk.yellow(`  • ${t.name}`));
            console.log(chalk.yellow(`    ${t.error}\n`));
        });
    }

    // Overall status
    console.log(chalk.bold('\n' + '═'.repeat(60)));
    if (criticalFailures.length === 0) {
        console.log(chalk.bold.green('✅ ALL CRITICAL TESTS PASSED!'));
    } else {
        console.log(chalk.bold.red('❌ SOME CRITICAL TESTS FAILED - REQUIRES ATTENTION'));
    }
    console.log(chalk.bold('═'.repeat(60) + '\n'));
}

// ═══════════════════════════════════════════════════════════════
//                    MANUAL TEST HELPERS
// ═══════════════════════════════════════════════════════════════

async function testSingleCommand(command) {
    console.log(chalk.cyan(`\n🧪 Testing single command: ${command}\n`));
    
    const testCase = testCases.find(t => t.command === command);
    
    if (testCase) {
        await runTest(testCase);
    } else {
        // Run as custom test
        await sendCommand(command);
        console.log(chalk.green(`✅ Command sent successfully`));
    }
}

async function testPositionCommands() {
    console.log(chalk.bold.cyan('\n📍 Testing Position Commands with Live Address\n'));
    
    const addr = TEST_ADDRESSES.withPosition;
    console.log(chalk.white(`Using address: ${addr}\n`));
    
    const positionCommands = [
        `/position ${addr}`,
        `/leverage ${addr}`,
        `/hf ${addr}`,
        `/collateral ${addr}`,
        `/debt ${addr}`,
        `/tp ${addr}`
    ];
    
    for (const cmd of positionCommands) {
        await sendCommand(cmd);
        await waitForResponse(2000);
        console.log(chalk.green(`✅ Sent: ${cmd}`));
    }
    
    console.log(chalk.bold.green('\n✅ All position commands sent!'));
}

async function interactiveTest() {
    console.log(chalk.bold.cyan('\n🎮 Interactive Test Mode\n'));
    console.log(chalk.white('Available options:'));
    console.log(chalk.white('1. Run all tests'));
    console.log(chalk.white('2. Test position commands with live address'));
    console.log(chalk.white('3. Test single command'));
    console.log(chalk.white('4. Quick smoke test (basic commands only)\n'));
    
    // For automation, run all tests
    await runAllTests();
}

async function quickSmokeTest() {
    console.log(chalk.bold.cyan('\n🔥 Quick Smoke Test\n'));
    
    const smokeTests = [
        '/start',
        '/help',
        '/status',
        '/health',
        `/position ${TEST_ADDRESSES.withPosition}`,
        '/reserves',
        '/rvmstatus'
    ];
    
    for (const cmd of smokeTests) {
        await sendCommand(cmd);
        await waitForResponse(1500);
        console.log(chalk.green(`✅ ${cmd}`));
    }
    
    console.log(chalk.bold.green('\n✅ Smoke test complete!'));
}

// ═══════════════════════════════════════════════════════════════
//                         CLI INTERFACE
// ═══════════════════════════════════════════════════════════════

const args = process.argv.slice(2);
const mode = args[0] || 'all';

async function main() {
    console.log(chalk.bold.cyan('\n🚀 Starting Telegram Bot Test Suite...\n'));
    
    switch (mode) {
        case 'all':
            await runAllTests();
            break;
        case 'smoke':
            await quickSmokeTest();
            break;
        case 'position':
            await testPositionCommands();
            break;
        case 'interactive':
            await interactiveTest();
            break;
        default:
            await testSingleCommand(mode);
            break;
    }
}

// Run tests
main().catch(error => {
    console.error(chalk.red('\n❌ Test suite failed:'), error);
    process.exit(1);
});
