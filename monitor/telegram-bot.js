#!/usr/bin/env node

/**
 * Telegram Bot for Reactive Auto-Looper Notifications
 * 
 * Provides real-time notifications for:
 * - Position updates (leverage changes, health factor)
 * - Loop step executions
 * - Unwind steps
 * - Emergency events
 * - RVM reactions
 * - Callback deliveries
 * - Take-profit/Stop-loss triggers
 * 
 * Bot Commands:
 *   /start - Initialize bot and show welcome message
 *   /status - Check system status
 *   /position <address> - Check position for address
 *   /health - Check all component health
 *   /help - Show available commands
 * 
 * Usage:
 *   node telegram-bot.js              # Start bot in interactive mode
 *   node telegram-bot.js --daemon     # Run as background daemon
 */

import { ethers } from 'ethers';
import chalk from 'chalk';
import dotenv from 'dotenv';
import { NETWORKS, CONTRACTS, TOPICS, ABIS, POSITION_STATES } from './config.js';
import logger from './logger.js';
import RnkClient from './rnk-client.js';

dotenv.config();

// ═══════════════════════════════════════════════════════════════
//                     TELEGRAM CONFIGURATION
// ═══════════════════════════════════════════════════════════════

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const TELEGRAM_CHAT_ID = process.env.TELEGRAM_CHAT_ID;

if (!TELEGRAM_BOT_TOKEN || !TELEGRAM_CHAT_ID) {
    console.error('❌ Missing environment variables: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID required');
    process.exit(1);
}
const TELEGRAM_API_BASE = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}`;

// ═══════════════════════════════════════════════════════════════
//                       PROVIDERS
// ═══════════════════════════════════════════════════════════════

const sepoliaProvider = new ethers.JsonRpcProvider(NETWORKS.sepolia.rpc);
const lasnaProvider = new ethers.JsonRpcProvider(NETWORKS.lasna.rpc);
const rnkClient = new RnkClient();

// ═══════════════════════════════════════════════════════════════
//                    TELEGRAM API FUNCTIONS
// ═══════════════════════════════════════════════════════════════

/**
 * Send a message to Telegram
 */
async function sendTelegramMessage(text, options = {}) {
    const chatId = options.chatId || TELEGRAM_CHAT_ID;
    
    try {
        const response = await fetch(`${TELEGRAM_API_BASE}/sendMessage`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                chat_id: chatId,
                text: text,
                parse_mode: 'HTML',
                disable_web_page_preview: true,
                ...options
            })
        });
        
        const result = await response.json();
        
        if (!result.ok) {
            console.error(chalk.red('Telegram API Error:'), result.description);
            return null;
        }
        
        return result;
    } catch (error) {
        console.error(chalk.red('Failed to send Telegram message:'), error.message);
        return null;
    }
}

/**
 * Get updates from Telegram (for commands)
 */
async function getUpdates(offset = 0) {
    try {
        const response = await fetch(`${TELEGRAM_API_BASE}/getUpdates?offset=${offset}&timeout=30`);
        const result = await response.json();
        return result.ok ? result.result : [];
    } catch (error) {
        console.error(chalk.red('Failed to get updates:'), error.message);
        return [];
    }
}

/**
 * Get bot info
 */
async function getBotInfo() {
    try {
        const response = await fetch(`${TELEGRAM_API_BASE}/getMe`);
        const result = await response.json();
        return result.ok ? result.result : null;
    } catch (error) {
        console.error(chalk.red('Failed to get bot info:'), error.message);
        return null;
    }
}

// ═══════════════════════════════════════════════════════════════
//                    NOTIFICATION FORMATTERS
// ═══════════════════════════════════════════════════════════════

/**
 * Format address for display
 */
function formatAddress(addr) {
    if (!addr) return 'N/A';
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

/**
 * Format leverage display (from 18 decimal)
 */
function formatLeverage(value) {
    if (!value) return '0.00';
    const num = parseFloat(ethers.formatEther(value));
    return num.toFixed(2);
}

/**
 * Format health factor (from 18 decimal)
 */
function formatHealthFactor(value) {
    if (!value) return '0.00';
    const num = parseFloat(ethers.formatEther(value));
    return num.toFixed(2);
}

/**
 * Get state emoji and name
 */
function getStateInfo(state) {
    const states = {
        0: { emoji: '⚪', name: 'IDLE' },
        1: { emoji: '🔄', name: 'LOOPING' },
        2: { emoji: '⏪', name: 'UNWINDING' },
        3: { emoji: '🚨', name: 'EMERGENCY' }
    };
    return states[state] || states[0];
}

/**
 * Get health factor emoji based on value
 */
function getHealthEmoji(hf) {
    const value = parseFloat(ethers.formatEther(hf || '0'));
    if (value >= 2.0) return '💚'; // Safe
    if (value >= 1.5) return '💛'; // Caution
    if (value >= 1.2) return '🧡'; // Warning
    return '❤️'; // Danger
}

// ═══════════════════════════════════════════════════════════════
//                    NOTIFICATION MESSAGES
// ═══════════════════════════════════════════════════════════════

export const Notifications = {
    /**
     * Welcome message
     */
    welcome() {
        return `
🤖 <b>Reactive Auto-Looper Bot</b>

Welcome to the Reactive Auto-Looper monitoring bot!

<b>📊 What I monitor:</b>
• Position updates & leverage changes
• Loop/Unwind step executions  
• Health factor alerts
• RVM reactions on Lasna
• Callback deliveries on Sepolia
• Take-profit/Stop-loss triggers

<b>🔗 Networks:</b>
• Origin/Dest: Sepolia (11155111)
• Reactive: Lasna (5318007)

<b>📝 Commands:</b>
/status - Check system status
/position &lt;address&gt; - Check position
/health - Component health check
/help - Show all commands

<i>You'll receive real-time notifications for all events!</i>
`;
    },

    /**
     * Position Updated notification
     */
    positionUpdated(data, txHash) {
        const stateInfo = getStateInfo(data.state);
        const healthEmoji = getHealthEmoji(data.healthFactor);
        
        return `
🔔 <b>Position Updated</b>

👤 User: <code>${formatAddress(data.user)}</code>
${stateInfo.emoji} State: <b>${stateInfo.name}</b>

📊 <b>Leverage</b>
├ Current: <b>${formatLeverage(data.currentLeverage)}x</b>
└ Target: ${formatLeverage(data.targetLeverage)}x

${healthEmoji} Health Factor: <b>${formatHealthFactor(data.healthFactor)}</b>
🔢 Iteration: ${data.iteration}

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View on Etherscan</a>
`;
    },

    /**
     * Loop Step Executed notification
     */
    loopStepExecuted(data, txHash) {
        return `
🔄 <b>Loop Step Executed</b>

👤 User: <code>${formatAddress(data.user)}</code>

📈 <b>Step Details</b>
├ Borrowed: ${ethers.formatEther(data.borrowed || '0')} 
├ Swapped: ${ethers.formatEther(data.swapped || '0')}
├ Supplied: ${ethers.formatEther(data.supplied || '0')}
└ New Leverage: <b>${formatLeverage(data.newLeverage)}x</b>

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Unwind Step Executed notification
     */
    unwindStepExecuted(data, txHash) {
        return `
⏪ <b>Unwind Step Executed</b>

👤 User: <code>${formatAddress(data.user)}</code>

📉 <b>Step Details</b>
├ Withdrawn: ${ethers.formatEther(data.withdrawn || '0')}
├ Swapped: ${ethers.formatEther(data.swapped || '0')}
├ Repaid: ${ethers.formatEther(data.repaid || '0')}
└ New Leverage: <b>${formatLeverage(data.newLeverage)}x</b>

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Position Closed notification
     */
    positionClosed(user, finalCollateral, txHash) {
        return `
✅ <b>Position Closed</b>

👤 User: <code>${formatAddress(user)}</code>
💰 Final Collateral: ${ethers.formatEther(finalCollateral || '0')}

🎉 Position successfully closed!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Emergency Stop notification
     */
    emergencyStop(user, reason, txHash) {
        return `
🚨 <b>EMERGENCY STOP</b>

👤 User: <code>${formatAddress(user)}</code>
⚠️ Reason: ${reason}

<b>Immediate attention required!</b>

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Health Factor Warning
     */
    healthFactorWarning(user, healthFactor) {
        const hf = parseFloat(ethers.formatEther(healthFactor));
        const severity = hf < 1.2 ? '🔴 CRITICAL' : hf < 1.5 ? '🟠 WARNING' : '🟡 CAUTION';
        
        return `
⚠️ <b>Health Factor Alert</b>

👤 User: <code>${formatAddress(user)}</code>
❤️ Health Factor: <b>${hf.toFixed(2)}</b>

${severity}
${hf < 1.2 ? '⚡ Emergency unwind may trigger!' : 'Monitor closely.'}
`;
    },

    /**
     * RVM Reaction notification
     */
    rvmReaction(txNum, hasCallback) {
        return `
⚡ <b>RVM Reaction Detected</b>

🔢 TX Number: ${txNum}
📤 Callback Emitted: ${hasCallback ? '✅ Yes' : '❌ No'}

${hasCallback ? '🔄 Waiting for callback delivery...' : '⏸ No action triggered'}
`;
    },

    /**
     * Callback Delivered notification  
     */
    callbackDelivered(user, positionId, newCycle) {
        return `
📬 <b>Callback Delivered!</b>

👤 User: <code>${formatAddress(user)}</code>
🆔 Position: ${positionId}
🔢 Cycle: ${newCycle}

✅ Automation cycle complete!
`;
    },

    /**
     * Take Profit Triggered
     */
    takeProfitTriggered(user, currentPrice, targetPrice, txHash) {
        return `
💰 <b>Take Profit Triggered!</b>

👤 User: <code>${formatAddress(user)}</code>
📈 Price: $${formatLeverage(currentPrice)}
🎯 Target: $${formatLeverage(targetPrice)}

🎉 Profit target reached! Unwinding...

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Stop Loss Triggered
     */
    stopLossTriggered(user, currentPrice, stopPrice, txHash) {
        return `
🛑 <b>Stop Loss Triggered!</b>

👤 User: <code>${formatAddress(user)}</code>
📉 Price: $${formatLeverage(currentPrice)}
🎯 Stop: $${formatLeverage(stopPrice)}

⚠️ Stop loss hit! Unwinding position...

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    // ═══════════════════════════════════════════════════════════════
    //              ADVANCED FEATURE NOTIFICATIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * Flash Leverage Executed
     */
    flashLeverageExecuted(user, flashAmount, finalLeverage, txHash) {
        return `
⚡ <b>Flash Leverage Executed!</b>

👤 User: <code>${formatAddress(user)}</code>
💰 Flash Amount: ${ethers.formatEther(flashAmount || '0')}
📈 Final Leverage: <b>${formatLeverage(finalLeverage)}x</b>

🚀 Instant leverage achieved!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Flash Unwind Executed
     */
    flashUnwindExecuted(user, flashAmount, finalLeverage, txHash) {
        return `
⚡ <b>Flash Unwind Executed!</b>

👤 User: <code>${formatAddress(user)}</code>
💰 Flash Amount: ${ethers.formatEther(flashAmount || '0')}
📉 Final Leverage: <b>${formatLeverage(finalLeverage)}x</b>

🚀 Instant unwind complete!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Position Created
     */
    positionCreated(user, collateralAsset, borrowAsset, targetLeverage, txHash) {
        return `
🆕 <b>Position Created!</b>

👤 User: <code>${formatAddress(user)}</code>
💎 Collateral: <code>${formatAddress(collateralAsset)}</code>
💵 Borrow: <code>${formatAddress(borrowAsset)}</code>
🎯 Target: <b>${formatLeverage(targetLeverage)}x</b>

🚀 New position started!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Circuit Breaker Triggered
     */
    circuitBreakerTriggered(user, deviation, txHash) {
        return `
🔴 <b>Circuit Breaker Triggered!</b>

👤 User: <code>${formatAddress(user)}</code>
📊 Price Deviation: ${(Number(deviation) / 100).toFixed(2)}%

⚠️ Operations paused due to abnormal price movement!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Gas Refilled
     */
    gasRefilled(reactiveContract, amount, txHash) {
        return `
⛽ <b>Gas Refilled!</b>

📍 Contract: <code>${formatAddress(reactiveContract)}</code>
💰 Amount: ${ethers.formatEther(amount || '0')} ETH

✅ Reactive gas topped up!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * RVM ID Updated
     */
    rvmIdUpdated(rvmId, txHash) {
        return `
🆔 <b>RVM ID Updated!</b>

📍 New RVM: <code>${rvmId}</code>

✅ Reactive VM identifier changed.

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Gas Budget Exceeded
     */
    gasBudgetExceeded(user, gasSpent, maxGas, txHash) {
        return `
⛽ <b>Gas Budget Exceeded!</b>

👤 User: <code>${formatAddress(user)}</code>
📊 Spent: ${ethers.formatEther(gasSpent || '0')} ETH
📊 Max: ${ethers.formatEther(maxGas || '0')} ETH

⚠️ Position paused - gas limit reached!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Loop Unprofitable
     */
    loopUnprofitable(user, supplyAPY, borrowAPY, txHash) {
        return `
📉 <b>Loop Unprofitable!</b>

👤 User: <code>${formatAddress(user)}</code>
📈 Supply APY: ${(Number(supplyAPY) / 100).toFixed(2)}%
📉 Borrow APY: ${(Number(borrowAPY) / 100).toFixed(2)}%

⚠️ Looping paused - negative yield spread!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * TWAP Interval Not Met
     */
    twapIntervalNotMet(user, lastBlock, currentBlock, requiredInterval) {
        return `
⏰ <b>TWAP Interval Not Met</b>

👤 User: <code>${formatAddress(user)}</code>
🔢 Last: Block ${lastBlock}
🔢 Current: Block ${currentBlock}
📏 Required: ${requiredInterval} blocks

⏳ Waiting for TWAP interval...
`;
    },

    /**
     * MEV Protection Triggered
     */
    mevProtectionTriggered(user, txHash) {
        return `
🛡️ <b>MEV Protection Triggered!</b>

👤 User: <code>${formatAddress(user)}</code>

⚠️ Salt mismatch detected - possible MEV attack blocked!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Batch Executed
     */
    batchExecuted(totalUsers, successCount, failCount, txHash) {
        return `
📦 <b>Batch Execution Complete!</b>

👥 Total Users: ${totalUsers}
✅ Success: ${successCount}
❌ Failed: ${failCount}

${failCount === 0 ? '🎉 All operations successful!' : '⚠️ Some operations failed'}

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Approval Magic Deposit
     */
    approvalMagicDeposit(user, token, amount, targetLeverage, txHash) {
        return `
✨ <b>Approval Magic Deposit!</b>

👤 User: <code>${formatAddress(user)}</code>
🪙 Token: <code>${formatAddress(token)}</code>
💰 Amount: ${ethers.formatEther(amount || '0')}
🎯 Target: <b>${formatLeverage(targetLeverage)}x</b>

🚀 Auto-deposit triggered by approval!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Price Triggered Unwind
     */
    priceTriggeredUnwind(user, currentLeverage, txHash) {
        return `
📉 <b>Price Triggered Unwind!</b>

👤 User: <code>${formatAddress(user)}</code>
📊 Leverage: <b>${formatLeverage(currentLeverage)}x</b>

⚠️ Emergency unwind due to price movement!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Health Check Executed
     */
    healthCheckExecuted(user, healthFactor, state, txHash) {
        const stateInfo = getStateInfo(state);
        const healthEmoji = getHealthEmoji(healthFactor);
        
        return `
🏥 <b>Health Check Executed</b>

👤 User: <code>${formatAddress(user)}</code>
${healthEmoji} Health: <b>${formatHealthFactor(healthFactor)}</b>
${stateInfo.emoji} State: ${stateInfo.name}

✅ CRON health check complete.

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Take Profit Config Set
     */
    takeProfitConfigSet(user, takeProfitPrice, stopLossPrice, txHash) {
        return `
🎯 <b>Take Profit Config Set!</b>

👤 User: <code>${formatAddress(user)}</code>
💰 Take Profit: $${formatLeverage(takeProfitPrice)}
🛑 Stop Loss: $${formatLeverage(stopLossPrice)}

✅ Limit orders configured!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Liquidation Detected
     */
    liquidationDetected(user, collateralAsset, debtAsset, debtToCover, liquidatedCollateral, txHash) {
        return `
🚨 <b>LIQUIDATION DETECTED!</b>

👤 User: <code>${formatAddress(user)}</code>
💎 Collateral: <code>${formatAddress(collateralAsset)}</code>
💵 Debt: <code>${formatAddress(debtAsset)}</code>
📉 Debt Covered: ${ethers.formatEther(debtToCover || '0')}
📉 Collateral Lost: ${ethers.formatEther(liquidatedCollateral || '0')}

⚠️ Guardian failed to protect position!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Guardian Failure
     */
    guardianFailure(user, debtLiquidated, reason, txHash) {
        return `
❌ <b>Guardian Failure!</b>

👤 User: <code>${formatAddress(user)}</code>
💸 Debt Liquidated: ${ethers.formatEther(debtLiquidated || '0')}
📝 Reason: ${reason}

⚠️ Automation failed to protect position!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Insufficient Pool Liquidity
     */
    insufficientPoolLiquidity(user, asset, requestedAmount, availableLiquidity, txHash) {
        return `
⚠️ <b>Insufficient Pool Liquidity</b>

👤 User: <code>${formatAddress(user)}</code>
🪙 Asset: <code>${formatAddress(asset)}</code>
📊 Requested: ${ethers.formatEther(requestedAmount || '0')}
📊 Available: ${ethers.formatEther(availableLiquidity || '0')}

⏸️ Operation delayed - waiting for liquidity.

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Swap Liquidity Failure
     */
    swapLiquidityFailure(user, tokenIn, tokenOut, amountIn, reason, txHash) {
        return `
⚠️ <b>Swap Liquidity Failure</b>

👤 User: <code>${formatAddress(user)}</code>
🔄 Swap: <code>${formatAddress(tokenIn)}</code> → <code>${formatAddress(tokenOut)}</code>
💰 Amount: ${ethers.formatEther(amountIn || '0')}
📝 Reason: ${reason}

⏸️ DEX swap failed - retrying later.

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Degraded Execution
     */
    degradedExecution(user, operation, requestedAmount, actualAmount, reason, txHash) {
        return `
⚡ <b>Degraded Execution</b>

👤 User: <code>${formatAddress(user)}</code>
📝 Operation: ${operation}
📊 Requested: ${ethers.formatEther(requestedAmount || '0')}
📊 Actual: ${ethers.formatEther(actualAmount || '0')}
📝 Reason: ${reason}

⚠️ Operation succeeded with reduced parameters.

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Automation Pipeline Executed
     */
    automationPipelineExecuted(user, step, success, attemptedAmount, details, txHash) {
        return `
🔄 <b>Automation Pipeline Executed</b>

👤 User: <code>${formatAddress(user)}</code>
📝 Step: ${step}
${success ? '✅' : '❌'} Status: ${success ? 'Success' : 'Failed'}
💰 Amount: ${ethers.formatEther(attemptedAmount || '0')}
📋 Details: ${details}

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * System Status message
     */
    systemStatus(status) {
        const { manager, reactive, reserves, subscription } = status;
        
        return `
📊 <b>System Status</b>

<b>🔷 AutoLooperManager (Sepolia)</b>
├ Status: ${manager.deployed ? '✅ Deployed' : '❌ Not Found'}
└ Address: <code>${formatAddress(CONTRACTS.manager)}</code>

<b>🔶 AutoLooperReactive (Lasna)</b>
├ Status: ${reactive.deployed ? '✅ Deployed' : '❌ Not Found'}
└ Address: <code>${formatAddress(CONTRACTS.reactiveContract)}</code>

<b>💰 Callback Reserves</b>
├ Amount: ${reserves.amount} ETH
└ Status: ${reserves.ok ? '✅ Funded' : '⚠️ Low/Empty'}

<b>📡 RVM Subscription</b>
└ Status: ${subscription.active ? '✅ Active' : '❌ Not Found'}
`;
    },

    /**
     * Position Info message
     */
    positionInfo(user, position) {
        if (!position || position.state === 0 && position.currentLeverage === '0') {
            return `
ℹ️ <b>Position Info</b>

👤 User: <code>${formatAddress(user)}</code>

❌ No active position found.
`;
        }
        
        const stateInfo = getStateInfo(position.state);
        const healthEmoji = getHealthEmoji(position.healthFactor);
        
        return `
ℹ️ <b>Position Info</b>

👤 User: <code>${formatAddress(user)}</code>
${stateInfo.emoji} State: <b>${stateInfo.name}</b>

<b>📊 Position Details</b>
├ Collateral: <code>${formatAddress(position.collateralAsset)}</code>
├ Borrow: <code>${formatAddress(position.borrowAsset)}</code>
├ Initial: ${ethers.formatEther(position.initialCollateral || '0')}
├ Target Leverage: ${formatLeverage(position.targetLeverage)}x
├ Current Leverage: ${formatLeverage(position.currentLeverage)}x
├ Iteration: ${position.iteration}/${position.maxIterations}
└ ${healthEmoji} Health Factor: ${formatHealthFactor(position.healthFactor)}

<b>🛡️ Safety Settings</b>
├ Min HF: ${formatHealthFactor(position.minHealthFactor)}
└ Slippage: ${(Number(position.slippageTolerance) / 100).toFixed(2)}%
`;
    },

    /**
     * E2E Test Started
     */
    e2eTestStarted() {
        return `
🧪 <b>E2E Test Started</b>

Testing full automation pipeline:
1️⃣ Open position on Sepolia
2️⃣ Wait for RVM reaction on Lasna
3️⃣ Wait for callback delivery

⏳ Test in progress...
`;
    },

    /**
     * E2E Test Result
     */
    e2eTestResult(success, details) {
        if (success) {
            return `
✅ <b>E2E Test PASSED!</b>

🎉 Full automation pipeline verified!

${details.map(d => `✓ ${d}`).join('\n')}

<b>The system is working correctly!</b>
`;
        } else {
            return `
❌ <b>E2E Test FAILED</b>

${details.map(d => `• ${d}`).join('\n')}

Check logs for more details.
`;
        }
    },

    /**
     * Funder notification - funds received
     */
    fundsReceived(amount, sender, txHash) {
        return `
💰 <b>Funds Received (Reactivate)</b>

📥 Amount: ${ethers.formatEther(amount || '0')} ETH
👤 From: <code>${formatAddress(sender)}</code>

✅ Gas funds collected!

🔗 <a href="${NETWORKS.sepolia.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Cover debt callback triggered
     */
    coverDebtTriggered(amount, txHash) {
        return `
⛽ <b>Cover Debt Triggered</b>

💵 Amount: ${ethers.formatEther(amount || '0')} ETH

🔄 Self-sustaining gas refill in progress...

🔗 <a href="${NETWORKS.lasna.explorer}/tx/${txHash}">View TX</a>
`;
    },

    /**
     * Help message
     */
    help() {
        return `
📚 <b>Available Commands</b>

<b>Status & Monitoring</b>
/start - Welcome message & setup
/status - Check all system components
/health - Quick health check
/position &lt;addr&gt; - Check specific position

<b>Information</b>
/contracts - Show contract addresses
/networks - Show network info
/help - This message

<b>📡 Event Notifications</b>
You'll automatically receive alerts for:
• Position updates
• Loop/Unwind executions
• Health factor warnings
• RVM reactions
• Callback deliveries
• Emergency events

<i>Bot running 24/7 for real-time monitoring!</i>
`;
    },

    /**
     * Contracts info
     */
    contracts() {
        return `
📝 <b>Contract Addresses</b>

<b>🔷 Sepolia (Origin/Destination)</b>
├ Manager: <code>${CONTRACTS.manager}</code>
├ Callback Proxy: <code>${CONTRACTS.callbackProxy}</code>
└ <a href="${NETWORKS.sepolia.explorer}/address/${CONTRACTS.manager}">View on Etherscan</a>

<b>🔶 Lasna (Reactive Network)</b>
├ RSC: <code>${CONTRACTS.reactiveContract}</code>
├ System: <code>${CONTRACTS.systemContract}</code>
└ <a href="${NETWORKS.lasna.explorer}/address/${CONTRACTS.reactiveContract}">View on Reactscan</a>

<b>🆔 RVM ID</b>
<code>${CONTRACTS.rvmId}</code>
`;
    },

    /**
     * Networks info
     */
    networks() {
        return `
🌐 <b>Network Configuration</b>

<b>🔷 Sepolia (Origin/Destination)</b>
├ Chain ID: 11155111
├ RPC: eth-sepolia.g.alchemy.com
└ Explorer: sepolia.etherscan.io

<b>🔶 Lasna (Reactive Network)</b>
├ Chain ID: 5318007
├ RPC: lasna-rpc.rnk.dev
└ Explorer: lasna.rnk.dev
`;
    }
};

// ═══════════════════════════════════════════════════════════════
//                     COMMAND HANDLERS
// ═══════════════════════════════════════════════════════════════

const commandHandlers = {
    async start(chatId) {
        await sendTelegramMessage(Notifications.welcome(), { chatId });
    },

    async help(chatId) {
        await sendTelegramMessage(Notifications.help(), { chatId });
    },

    async contracts(chatId) {
        await sendTelegramMessage(Notifications.contracts(), { chatId });
    },

    async networks(chatId) {
        await sendTelegramMessage(Notifications.networks(), { chatId });
    },

    async status(chatId) {
        const status = {
            manager: { deployed: false },
            reactive: { deployed: false },
            reserves: { amount: '0', ok: false },
            subscription: { active: false }
        };

        try {
            // Check manager
            const managerCode = await sepoliaProvider.getCode(CONTRACTS.manager);
            status.manager.deployed = managerCode !== '0x';

            // Check reactive
            const reactiveCode = await lasnaProvider.getCode(CONTRACTS.reactiveContract);
            status.reactive.deployed = reactiveCode !== '0x';

            // Check reserves
            const proxyAbi = ['function reserves(address) view returns (uint256)'];
            const proxy = new ethers.Contract(CONTRACTS.callbackProxy, proxyAbi, sepoliaProvider);
            const reserves = await proxy.reserves(CONTRACTS.rvmId);
            status.reserves.amount = ethers.formatEther(reserves);
            status.reserves.ok = reserves > 0n;

            // Check subscription
            const subs = await rnkClient.getSubscribers(CONTRACTS.rvmId);
            status.subscription.active = subs?.some(s => 
                s.contract.toLowerCase() === CONTRACTS.manager.toLowerCase() &&
                s.topics[0]?.toLowerCase() === TOPICS.PositionUpdated.toLowerCase()
            );
        } catch (e) {
            console.error('Error checking status:', e.message);
        }

        await sendTelegramMessage(Notifications.systemStatus(status), { chatId });
    },

    async health(chatId) {
        let healthMsg = '🏥 <b>Quick Health Check</b>\n\n';
        
        try {
            // Manager
            const mCode = await sepoliaProvider.getCode(CONTRACTS.manager);
            healthMsg += mCode !== '0x' ? '✅ Manager: Online\n' : '❌ Manager: Offline\n';

            // Reactive
            const rCode = await lasnaProvider.getCode(CONTRACTS.reactiveContract);
            healthMsg += rCode !== '0x' ? '✅ Reactive: Online\n' : '❌ Reactive: Offline\n';

            // Reserves
            const proxyAbi = ['function reserves(address) view returns (uint256)'];
            const proxy = new ethers.Contract(CONTRACTS.callbackProxy, proxyAbi, sepoliaProvider);
            const reserves = await proxy.reserves(CONTRACTS.rvmId);
            healthMsg += reserves > 0n ? `✅ Reserves: ${ethers.formatEther(reserves)} ETH\n` : '⚠️ Reserves: Empty!\n';

        } catch (e) {
            healthMsg += `\n❌ Error: ${e.message}`;
        }

        await sendTelegramMessage(healthMsg, { chatId });
    },

    async position(chatId, args) {
        const userAddr = args[0];
        if (!userAddr || !ethers.isAddress(userAddr)) {
            await sendTelegramMessage('⚠️ Please provide a valid address:\n/position &lt;address&gt;', { chatId });
            return;
        }

        try {
            const manager = new ethers.Contract(CONTRACTS.manager, [
                'function getPosition(address user) view returns (tuple(address collateralAsset, address borrowAsset, uint256 initialCollateral, uint256 targetLeverage, uint256 currentLeverage, uint256 maxIterations, uint256 currentIteration, uint256 minHealthFactor, uint256 slippageTolerance, uint8 state, uint256 lastUpdateBlock, bool useFlashLoan, bool sameAssetLoop))',
                'function getHealthFactor(address user) view returns (uint256)'
            ], sepoliaProvider);

            const pos = await manager.getPosition(userAddr);
            const hf = await manager.getHealthFactor(userAddr);

            const positionData = {
                collateralAsset: pos.collateralAsset,
                borrowAsset: pos.borrowAsset,
                initialCollateral: pos.initialCollateral.toString(),
                targetLeverage: pos.targetLeverage.toString(),
                currentLeverage: pos.currentLeverage.toString(),
                maxIterations: pos.maxIterations.toString(),
                iteration: pos.currentIteration.toString(),
                minHealthFactor: pos.minHealthFactor.toString(),
                slippageTolerance: pos.slippageTolerance.toString(),
                state: Number(pos.state),
                healthFactor: hf.toString()
            };

            await sendTelegramMessage(Notifications.positionInfo(userAddr, positionData), { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error fetching position: ${e.message}`, { chatId });
        }
    }
};

// ═══════════════════════════════════════════════════════════════
//                    MESSAGE PROCESSOR
// ═══════════════════════════════════════════════════════════════

async function processMessage(message) {
    const chatId = message.chat.id;
    const text = message.text || '';
    
    if (!text.startsWith('/')) return;
    
    const parts = text.split(' ');
    const command = parts[0].replace('/', '').replace('@AutoLooperBot', '').toLowerCase();
    const args = parts.slice(1);
    
    if (commandHandlers[command]) {
        await commandHandlers[command](chatId, args);
    } else {
        await sendTelegramMessage('❓ Unknown command. Use /help to see available commands.', { chatId });
    }
}

// ═══════════════════════════════════════════════════════════════
//                     EVENT LISTENERS
// ═══════════════════════════════════════════════════════════════

const managerInterface = new ethers.Interface([
    // Core events
    'event PositionUpdated(address indexed user, uint256 currentLeverage, uint256 targetLeverage, uint256 healthFactor, uint256 iteration, uint8 state)',
    'event LoopStepExecuted(address indexed user, uint256 borrowed, uint256 swapped, uint256 supplied, uint256 newLeverage)',
    'event UnwindStepExecuted(address indexed user, uint256 withdrawn, uint256 swapped, uint256 repaid, uint256 newLeverage)',
    'event PositionClosed(address indexed user, uint256 finalCollateral)',
    'event PositionCreated(address indexed user, address collateralAsset, address borrowAsset, uint256 targetLeverage)',
    'event EmergencyStop(address indexed user, string reason)',
    
    // Take profit / Stop loss
    'event TakeProfitTriggered(address indexed user, uint256 currentPrice, uint256 takeProfitPrice)',
    'event StopLossTriggered(address indexed user, uint256 currentPrice, uint256 stopLossPrice)',
    'event TakeProfitConfigSet(address indexed user, uint256 takeProfitPrice, uint256 stopLossPrice)',
    
    // Flash loan events
    'event FlashLeverageExecuted(address indexed user, uint256 flashAmount, uint256 finalLeverage)',
    'event FlashUnwindExecuted(address indexed user, uint256 flashAmount, uint256 finalLeverage)',
    
    // Advanced feature events
    'event CircuitBreakerTriggered(address indexed user, uint256 deviation)',
    'event GasRefilled(address indexed reactiveContract, uint256 amount)',
    'event RvmIdUpdated(address indexed rvmId)',
    'event GasBudgetExceeded(address indexed user, uint256 gasSpent, uint256 maxGas)',
    'event LoopUnprofitable(address indexed user, uint256 supplyAPY, uint256 borrowAPY)',
    'event TwapIntervalNotMet(address indexed user, uint256 lastBlock, uint256 currentBlock, uint256 requiredInterval)',
    'event MevProtectionTriggered(address indexed user, bytes32 expectedSalt, bytes32 providedSalt)',
    'event BatchExecuted(uint256 totalUsers, uint256 successCount, uint256 failCount)',
    'event ApprovalMagicDeposit(address indexed user, address indexed token, uint256 amount, uint256 targetLeverage)',
    'event PriceTriggeredUnwind(address indexed user, uint256 currentLeverage)',
    'event HealthCheckExecuted(address indexed user, uint256 healthFactor, uint8 state)',
    
    // Liquidation events
    'event LiquidationDetected(address indexed user, address indexed collateralAsset, address indexed debtAsset, uint256 debtToCover, uint256 liquidatedCollateral, bool receiveAToken)',
    'event GuardianFailure(address indexed user, uint256 debtLiquidated, string reason)',
    
    // Liquidity failure events
    'event InsufficientPoolLiquidity(address indexed user, address indexed asset, uint256 requestedAmount, uint256 availableLiquidity)',
    'event SwapLiquidityFailure(address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, string reason)',
    'event DegradedExecution(address indexed user, string operation, uint256 requestedAmount, uint256 actualAmount, string reason)',
    'event AutomationPipelineExecuted(address indexed user, string step, bool success, uint256 attemptedAmount, string details)'
]);

function setupEventListeners() {
    const manager = new ethers.Contract(CONTRACTS.manager, managerInterface, sepoliaProvider);

    // Position Updated
    manager.on('PositionUpdated', async (user, currentLeverage, targetLeverage, healthFactor, iteration, state, event) => {
        const data = { user, currentLeverage, targetLeverage, healthFactor, iteration: iteration.toString(), state: Number(state) };
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.positionUpdated(data, txHash));
        
        // Check for health factor warning
        const hf = parseFloat(ethers.formatEther(healthFactor));
        if (hf < 1.5 && hf > 0) {
            await sendTelegramMessage(Notifications.healthFactorWarning(user, healthFactor));
        }
    });

    // Loop Step Executed
    manager.on('LoopStepExecuted', async (user, borrowed, swapped, supplied, newLeverage, event) => {
        const data = { user, borrowed, swapped, supplied, newLeverage };
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.loopStepExecuted(data, txHash));
    });

    // Unwind Step Executed
    manager.on('UnwindStepExecuted', async (user, withdrawn, swapped, repaid, newLeverage, event) => {
        const data = { user, withdrawn, swapped, repaid, newLeverage };
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.unwindStepExecuted(data, txHash));
    });

    // Position Closed
    manager.on('PositionClosed', async (user, finalCollateral, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.positionClosed(user, finalCollateral, txHash));
    });

    // Position Created
    manager.on('PositionCreated', async (user, collateralAsset, borrowAsset, targetLeverage, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.positionCreated(user, collateralAsset, borrowAsset, targetLeverage, txHash));
    });

    // Emergency Stop
    manager.on('EmergencyStop', async (user, reason, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.emergencyStop(user, reason, txHash));
    });

    // Take Profit
    manager.on('TakeProfitTriggered', async (user, currentPrice, takeProfitPrice, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.takeProfitTriggered(user, currentPrice, takeProfitPrice, txHash));
    });

    // Stop Loss
    manager.on('StopLossTriggered', async (user, currentPrice, stopLossPrice, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.stopLossTriggered(user, currentPrice, stopLossPrice, txHash));
    });

    // Take Profit Config Set
    manager.on('TakeProfitConfigSet', async (user, takeProfitPrice, stopLossPrice, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.takeProfitConfigSet(user, takeProfitPrice, stopLossPrice, txHash));
    });

    // Flash Leverage Executed
    manager.on('FlashLeverageExecuted', async (user, flashAmount, finalLeverage, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.flashLeverageExecuted(user, flashAmount, finalLeverage, txHash));
    });

    // Flash Unwind Executed
    manager.on('FlashUnwindExecuted', async (user, flashAmount, finalLeverage, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.flashUnwindExecuted(user, flashAmount, finalLeverage, txHash));
    });

    // Circuit Breaker Triggered
    manager.on('CircuitBreakerTriggered', async (user, deviation, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.circuitBreakerTriggered(user, deviation, txHash));
    });

    // Gas Refilled
    manager.on('GasRefilled', async (reactiveContract, amount, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.gasRefilled(reactiveContract, amount, txHash));
    });

    // RVM ID Updated
    manager.on('RvmIdUpdated', async (rvmId, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.rvmIdUpdated(rvmId, txHash));
    });

    // Gas Budget Exceeded
    manager.on('GasBudgetExceeded', async (user, gasSpent, maxGas, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.gasBudgetExceeded(user, gasSpent, maxGas, txHash));
    });

    // Loop Unprofitable
    manager.on('LoopUnprofitable', async (user, supplyAPY, borrowAPY, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.loopUnprofitable(user, supplyAPY, borrowAPY, txHash));
    });

    // TWAP Interval Not Met
    manager.on('TwapIntervalNotMet', async (user, lastBlock, currentBlock, requiredInterval, event) => {
        await sendTelegramMessage(Notifications.twapIntervalNotMet(user, lastBlock.toString(), currentBlock.toString(), requiredInterval.toString()));
    });

    // MEV Protection Triggered
    manager.on('MevProtectionTriggered', async (user, expectedSalt, providedSalt, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.mevProtectionTriggered(user, txHash));
    });

    // Batch Executed
    manager.on('BatchExecuted', async (totalUsers, successCount, failCount, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.batchExecuted(totalUsers.toString(), successCount.toString(), failCount.toString(), txHash));
    });

    // Approval Magic Deposit
    manager.on('ApprovalMagicDeposit', async (user, token, amount, targetLeverage, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.approvalMagicDeposit(user, token, amount, targetLeverage, txHash));
    });

    // Price Triggered Unwind
    manager.on('PriceTriggeredUnwind', async (user, currentLeverage, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.priceTriggeredUnwind(user, currentLeverage, txHash));
    });

    // Health Check Executed
    manager.on('HealthCheckExecuted', async (user, healthFactor, state, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.healthCheckExecuted(user, healthFactor, state, txHash));
    });

    // Liquidation Detected
    manager.on('LiquidationDetected', async (user, collateralAsset, debtAsset, debtToCover, liquidatedCollateral, receiveAToken, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.liquidationDetected(user, collateralAsset, debtAsset, debtToCover, liquidatedCollateral, txHash));
    });

    // Guardian Failure
    manager.on('GuardianFailure', async (user, debtLiquidated, reason, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.guardianFailure(user, debtLiquidated, reason, txHash));
    });

    // Insufficient Pool Liquidity
    manager.on('InsufficientPoolLiquidity', async (user, asset, requestedAmount, availableLiquidity, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.insufficientPoolLiquidity(user, asset, requestedAmount, availableLiquidity, txHash));
    });

    // Swap Liquidity Failure
    manager.on('SwapLiquidityFailure', async (user, tokenIn, tokenOut, amountIn, reason, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.swapLiquidityFailure(user, tokenIn, tokenOut, amountIn, reason, txHash));
    });

    // Degraded Execution
    manager.on('DegradedExecution', async (user, operation, requestedAmount, actualAmount, reason, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.degradedExecution(user, operation, requestedAmount, actualAmount, reason, txHash));
    });

    // Automation Pipeline Executed
    manager.on('AutomationPipelineExecuted', async (user, step, success, attemptedAmount, details, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(Notifications.automationPipelineExecuted(user, step, success, attemptedAmount, details, txHash));
    });

    logger.success('Event listeners configured for Sepolia (30 event types)');
}

// ═══════════════════════════════════════════════════════════════
//                      MAIN BOT LOOP
// ═══════════════════════════════════════════════════════════════

async function startBot() {
    console.log('');
    console.log(chalk.bold.cyan('╔════════════════════════════════════════════════════════════════╗'));
    console.log(chalk.bold.cyan('║         REACTIVE AUTO-LOOPER TELEGRAM BOT                      ║'));
    console.log(chalk.bold.cyan('╚════════════════════════════════════════════════════════════════╝'));
    console.log('');

    // Verify bot token
    const botInfo = await getBotInfo();
    if (!botInfo) {
        logger.error('Failed to connect to Telegram. Check your bot token.');
        process.exit(1);
    }
    
    logger.success(`Connected as @${botInfo.username}`);
    logger.info(`Chat ID: ${TELEGRAM_CHAT_ID}`);
    console.log('');

    // Send startup message
    await sendTelegramMessage(`
🚀 <b>Bot Started!</b>

✅ Reactive Auto-Looper monitoring is now active.
📡 Listening for events on Sepolia & Lasna.

Use /help to see available commands.
`);

    // Setup event listeners
    setupEventListeners();

    // Command polling loop
    let offset = 0;
    logger.info('Listening for commands...');
    
    while (true) {
        try {
            const updates = await getUpdates(offset);
            
            for (const update of updates) {
                offset = update.update_id + 1;
                
                if (update.message) {
                    await processMessage(update.message);
                }
            }
        } catch (error) {
            console.error(chalk.red('Error in bot loop:'), error.message);
        }
        
        // Small delay between update checks
        await new Promise(r => setTimeout(r, 1000));
    }
}

// ═══════════════════════════════════════════════════════════════
//                     EXPORTS FOR E2E
// ═══════════════════════════════════════════════════════════════

export {
    sendTelegramMessage,
    TELEGRAM_CHAT_ID,
    TELEGRAM_BOT_TOKEN
};

export default {
    sendTelegramMessage,
    Notifications,
    start: startBot
};

// Start if run directly
if (process.argv[1] && process.argv[1].includes('telegram-bot.js')) {    startBot().catch(console.error);
}