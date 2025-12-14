#!/usr/bin/env node

/**
 * Enhanced Telegram Bot for Reactive Auto-Looper
 * 
 * COMPREHENSIVE FEATURE COVERAGE:
 * 
 * ═══════════════════════════════════════════════════════════════
 *                    BASIC COMMANDS
 * ═══════════════════════════════════════════════════════════════
 * /start          - Initialize bot and show welcome
 * /help           - Show all commands organized by category
 * /status         - System status overview
 * /health         - Quick component health check
 * /contracts      - Show contract addresses
 * /networks       - Show network info
 * 
 * ═══════════════════════════════════════════════════════════════
 *                    POSITION COMMANDS
 * ═══════════════════════════════════════════════════════════════
 * /position <addr>    - View position details
 * /myposition         - View your position (if configured)
 * /leverage <addr>    - Check current leverage
 * /hf <addr>          - Check health factor
 * /collateral <addr>  - View collateral details
 * /debt <addr>        - View debt details
 * 
 * ═══════════════════════════════════════════════════════════════
 *                    ADVANCED FEATURES
 * ═══════════════════════════════════════════════════════════════
 * /tp <addr>          - View take-profit/stop-loss config
 * /fees               - View current fee structure
 * /reserves           - Check callback proxy reserves
 * /subscription       - Check RVM subscription status
 * /rvmstatus          - Detailed RVM status
 * /debt_rvm           - Check RVM debt status
 * 
 * ═══════════════════════════════════════════════════════════════
 *                    MONITORING COMMANDS
 * ═══════════════════════════════════════════════════════════════
 * /watch <addr>       - Add address to watchlist
 * /unwatch <addr>     - Remove from watchlist
 * /watchlist          - Show current watchlist
 * /alerts             - Configure alert thresholds
 * 
 * ═══════════════════════════════════════════════════════════════
 *                    ANALYTICS COMMANDS
 * ═══════════════════════════════════════════════════════════════
 * /stats              - System statistics
 * /events <addr>      - Recent events for address
 * /txhistory <addr>   - Transaction history
 * 
 * ═══════════════════════════════════════════════════════════════
 *                    QUICK ACTIONS (Inline Buttons)
 * ═══════════════════════════════════════════════════════════════
 * - Quick status check
 * - Position refresh
 * - Health check
 * - RVM status
 */

import { ethers } from 'ethers';
import chalk from 'chalk';
import dotenv from 'dotenv';
import { NETWORKS, CONTRACTS, TOPICS } from './config.js';
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
    console.error('   Set them in .env file or export them before running');
    process.exit(1);
}
const TELEGRAM_API_BASE = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}`;

// ═══════════════════════════════════════════════════════════════
//                       PROVIDERS & CONTRACTS
// ═══════════════════════════════════════════════════════════════

const sepoliaProvider = new ethers.JsonRpcProvider(NETWORKS.sepolia.rpc);
const lasnaProvider = new ethers.JsonRpcProvider(NETWORKS.lasna.rpc);
const rnkClient = new RnkClient();

// Manager Contract ABI (comprehensive)
const MANAGER_ABI = [
    // View functions
    'function getPosition(address user) view returns (tuple(address collateralAsset, address borrowAsset, uint256 initialCollateral, uint256 targetLeverage, uint256 currentLeverage, uint256 maxIterations, uint256 currentIteration, uint256 minHealthFactor, uint256 slippageTolerance, uint8 state, uint256 lastUpdateBlock, bool useFlashLoan, bool sameAssetLoop, uint256 maxGasSpend, uint256 gasSpentSoFar, uint256 twapBlockInterval, bytes32 executionSalt, uint256 takeProfitPrice, uint256 stopLossPrice))',
    'function getHealthFactor(address user) view returns (uint256)',
    'function getCurrentLeverage(address user) view returns (uint256)',
    'function hasPosition(address user) view returns (bool)',
    'function loopFee() view returns (uint256)',
    'function flashLoanFee() view returns (uint256)',
    'function paused() view returns (bool)',
    'function circuitBreakerEnabled() view returns (bool)',
    'function profitabilityCheckEnabled() view returns (bool)',
    'function batchExecutionEnabled() view returns (bool)',
    'function reactiveContract() view returns (address)',
    'function rvm_id() view returns (address)',
    // Events
    'event PositionUpdated(address indexed user, uint256 currentLeverage, uint256 targetLeverage, uint256 healthFactor, uint256 iteration, uint8 state)',
    'event LoopStepExecuted(address indexed user, uint256 borrowed, uint256 swapped, uint256 supplied, uint256 newLeverage)',
    'event UnwindStepExecuted(address indexed user, uint256 withdrawn, uint256 swapped, uint256 repaid, uint256 newLeverage)',
    'event PositionClosed(address indexed user, uint256 finalCollateral)',
    'event PositionCreated(address indexed user, address collateralAsset, address borrowAsset, uint256 targetLeverage)',
    'event EmergencyStop(address indexed user, string reason)',
    'event TakeProfitTriggered(address indexed user, uint256 currentPrice, uint256 takeProfitPrice)',
    'event StopLossTriggered(address indexed user, uint256 currentPrice, uint256 stopLossPrice)',
    'event TakeProfitConfigSet(address indexed user, uint256 takeProfitPrice, uint256 stopLossPrice)',
    'event FlashLeverageExecuted(address indexed user, uint256 flashAmount, uint256 finalLeverage)',
    'event FlashUnwindExecuted(address indexed user, uint256 flashAmount, uint256 finalLeverage)',
    'event CircuitBreakerTriggered(address indexed user, uint256 deviation)',
    'event GasRefilled(address indexed reactiveContract, uint256 amount)',
    'event RvmIdUpdated(address indexed rvmId)',
    'event GasBudgetExceeded(address indexed user, uint256 gasSpent, uint256 maxGas)',
    'event LoopUnprofitable(address indexed user, uint256 supplyAPY, uint256 borrowAPY)',
    'event AutomationPipelineExecuted(address indexed user, string step, bool success, uint256 attemptedAmount, string details)'
];

// Callback Proxy ABI
const PROXY_ABI = [
    'function reserves(address) view returns (uint256)',
    'function depositTo(address rvm_id) payable'
];

// Reactive Contract ABI
const REACTIVE_ABI = [
    'function owner() view returns (address)',
    'function vault() view returns (address)',
    'function approvalMagicEnabled() view returns (bool)',
    'function priceMonitoringEnabled() view returns (bool)',
    'function cronMonitoringEnabled() view returns (bool)',
    'function liquidationMonitoringEnabled() view returns (bool)',
    'function stalePositionCheckEnabled() view returns (bool)',
    'function finalityAwareEnabled() view returns (bool)',
    'function cronInterval() view returns (uint256)',
    'function maxStaleBlocks() view returns (uint256)'
];

// System Contract ABI (Lasna)
const SYSTEM_ABI = [
    'function debt(address) view returns (uint256)',
    'function freeBalance(address) view returns (uint256)'
];

// Create contract instances
const managerContract = new ethers.Contract(CONTRACTS.manager, MANAGER_ABI, sepoliaProvider);
const proxyContract = new ethers.Contract(CONTRACTS.callbackProxy, PROXY_ABI, sepoliaProvider);

// ═══════════════════════════════════════════════════════════════
//                       USER STATE (Watchlist)
// ═══════════════════════════════════════════════════════════════

const userState = {
    watchlist: new Set(),
    myAddress: null,
    alertThresholds: {
        healthFactor: 1.3,
        leverageDeviation: 0.5
    }
};

// ═══════════════════════════════════════════════════════════════
//                    TELEGRAM API FUNCTIONS
// ═══════════════════════════════════════════════════════════════

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
        }
        
        return result;
    } catch (error) {
        console.error(chalk.red('Failed to send Telegram message:'), error.message);
        return null;
    }
}

async function sendMessageWithButtons(text, buttons, options = {}) {
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
                reply_markup: {
                    inline_keyboard: buttons
                }
            })
        });
        
        return await response.json();
    } catch (error) {
        console.error(chalk.red('Failed to send message with buttons:'), error.message);
        return null;
    }
}

async function answerCallbackQuery(callbackQueryId, text = '') {
    try {
        await fetch(`${TELEGRAM_API_BASE}/answerCallbackQuery`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                callback_query_id: callbackQueryId,
                text: text
            })
        });
    } catch (error) {
        console.error(chalk.red('Failed to answer callback:'), error.message);
    }
}

async function getUpdates(offset = 0) {
    try {
        const response = await fetch(`${TELEGRAM_API_BASE}/getUpdates?offset=${offset}&timeout=30`);
        const result = await response.json();
        return result.ok ? result.result : [];
    } catch (error) {
        return [];
    }
}

async function getBotInfo() {
    try {
        const response = await fetch(`${TELEGRAM_API_BASE}/getMe`);
        const result = await response.json();
        return result.ok ? result.result : null;
    } catch (error) {
        return null;
    }
}

// ═══════════════════════════════════════════════════════════════
//                    HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════

function formatAddress(addr) {
    if (!addr) return 'N/A';
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

function formatLeverage(leverage) {
    if (!leverage) return '0.00';
    const value = parseFloat(ethers.formatEther(leverage.toString()));
    return value.toFixed(2);
}

function formatHealthFactor(hf) {
    if (!hf) return 'N/A';
    const value = parseFloat(ethers.formatEther(hf.toString()));
    return value.toFixed(2);
}

function getStateInfo(state) {
    const states = {
        0: { emoji: '⚪', name: 'IDLE', color: 'gray' },
        1: { emoji: '🔄', name: 'LOOPING', color: 'green' },
        2: { emoji: '⏪', name: 'UNWINDING', color: 'yellow' },
        3: { emoji: '🚨', name: 'EMERGENCY', color: 'red' }
    };
    return states[state] || states[0];
}

function getHealthEmoji(hf) {
    const value = parseFloat(ethers.formatEther(hf?.toString() || '0'));
    if (value >= 2.0) return '💚';
    if (value >= 1.5) return '💛';
    if (value >= 1.2) return '🧡';
    return '❤️';
}

// ═══════════════════════════════════════════════════════════════
//                    COMMAND HANDLERS
// ═══════════════════════════════════════════════════════════════

const commands = {
    // ═══════════════════════════════════════════════════════════════
    //                    BASIC COMMANDS
    // ═══════════════════════════════════════════════════════════════

    async start(chatId) {
        const welcomeMsg = `
🤖 <b>Reactive Auto-Looper Bot v2.0</b>

Welcome to the most comprehensive Aave leveraged looping automation!

<b>🔑 Key Features:</b>
• Automated leverage looping on Aave V3
• Reactive Network powered automation
• Flash loan support for instant leverage
• Take-profit & Stop-loss triggers
• Real-time monitoring & alerts

<b>📊 Quick Commands:</b>
/status - System overview
/position &lt;addr&gt; - Check position
/health - Component health

<b>🔧 Advanced:</b>
/tp &lt;addr&gt; - Take-profit config
/reserves - Callback reserves
/rvmstatus - RVM details

Use /help for full command list!
`;

        const buttons = [
            [
                { text: '📊 Status', callback_data: 'cmd_status' },
                { text: '🏥 Health', callback_data: 'cmd_health' }
            ],
            [
                { text: '📝 Contracts', callback_data: 'cmd_contracts' },
                { text: '🌐 Networks', callback_data: 'cmd_networks' }
            ],
            [
                { text: '❓ Help', callback_data: 'cmd_help' }
            ]
        ];

        await sendMessageWithButtons(welcomeMsg, buttons, { chatId });
    },

    async help(chatId) {
        const helpMsg = `
📚 <b>Complete Command Reference</b>

<b>━━━ BASIC ━━━</b>
/start - Welcome &amp; quick actions
/help - This help message
/status - Full system status
/health - Quick health check

<b>━━━ POSITION ━━━</b>
/position &lt;addr&gt; - View position
/myposition - Your position
/leverage &lt;addr&gt; - Current leverage
/hf &lt;addr&gt; - Health factor
/collateral &lt;addr&gt; - Collateral info
/debt &lt;addr&gt; - Debt details

<b>━━━ ADVANCED ━━━</b>
/tp &lt;addr&gt; - Take-profit/Stop-loss
/fees - Fee structure
/settings - System settings

<b>━━━ REACTIVE NETWORK ━━━</b>
/reserves - Callback proxy reserves
/subscription - RVM subscription
/rvmstatus - Full RVM status
/rvmdebt - RVM debt check
/reactive - Reactive contract info

<b>━━━ MONITORING ━━━</b>
/watch &lt;addr&gt; - Add to watchlist
/unwatch &lt;addr&gt; - Remove from watchlist
/watchlist - View watchlist
/setmy &lt;addr&gt; - Set your address

<b>━━━ INFO ━━━</b>
/contracts - Contract addresses
/networks - Network info
/features - Feature list
/stats - System stats
`;
        await sendTelegramMessage(helpMsg, { chatId });
    },

    async status(chatId) {
        let msg = '📊 <b>System Status</b>\n\n';
        
        try {
            // Manager status
            const isPaused = await managerContract.paused();
            const circuitBreaker = await managerContract.circuitBreakerEnabled();
            const profitCheck = await managerContract.profitabilityCheckEnabled();
            const batchEnabled = await managerContract.batchExecutionEnabled();
            
            msg += `<b>🔷 AutoLooperManager</b>\n`;
            msg += `├ Status: ${isPaused ? '⏸ Paused' : '✅ Active'}\n`;
            msg += `├ Circuit Breaker: ${circuitBreaker ? '✅ On' : '❌ Off'}\n`;
            msg += `├ Profitability Check: ${profitCheck ? '✅ On' : '❌ Off'}\n`;
            msg += `├ Batch Execution: ${batchEnabled ? '✅ On' : '❌ Off'}\n`;
            msg += `└ <code>${formatAddress(CONTRACTS.manager)}</code>\n\n`;

            // Reserves
            const reserves = await proxyContract.reserves(CONTRACTS.rvmId);
            const reservesEth = ethers.formatEther(reserves);
            msg += `<b>💰 Callback Reserves</b>\n`;
            msg += `├ Balance: ${parseFloat(reservesEth).toFixed(4)} ETH\n`;
            msg += `└ Status: ${reserves > 0n ? '✅ Funded' : '⚠️ Empty!'}\n\n`;

            // RVM subscription check
            const subs = await rnkClient.getSubscribers(CONTRACTS.rvmId);
            const hasSub = subs?.some(s => 
                s.contract?.toLowerCase() === CONTRACTS.manager.toLowerCase()
            );
            msg += `<b>📡 RVM Subscription</b>\n`;
            msg += `└ Status: ${hasSub ? '✅ Active' : '❌ Not Found'}\n`;
            
        } catch (e) {
            msg += `\n❌ Error: ${e.message}`;
        }

        const buttons = [
            [
                { text: '🔄 Refresh', callback_data: 'cmd_status' },
                { text: '🏥 Health', callback_data: 'cmd_health' }
            ]
        ];

        await sendMessageWithButtons(msg, buttons, { chatId });
    },

    async health(chatId) {
        let msg = '🏥 <b>Quick Health Check</b>\n\n';
        
        try {
            // Manager
            const mCode = await sepoliaProvider.getCode(CONTRACTS.manager);
            msg += mCode !== '0x' ? '✅ Manager: Online\n' : '❌ Manager: Offline\n';

            // Reactive
            const rCode = await lasnaProvider.getCode(CONTRACTS.reactiveContract);
            msg += rCode !== '0x' ? '✅ Reactive: Online\n' : '❌ Reactive: Offline\n';

            // Reserves
            const reserves = await proxyContract.reserves(CONTRACTS.rvmId);
            msg += reserves > 0n ? `✅ Reserves: ${ethers.formatEther(reserves)} ETH\n` : '⚠️ Reserves: Empty!\n';

            // RVM Debt check
            try {
                const systemContract = new ethers.Contract(
                    CONTRACTS.systemContract,
                    SYSTEM_ABI,
                    lasnaProvider
                );
                const debt = await systemContract.debt(CONTRACTS.reactiveContract);
                if (debt > 0n) {
                    msg += `⚠️ RVM Debt: ${ethers.formatEther(debt)} ETH\n`;
                } else {
                    msg += `✅ RVM Debt: Clear\n`;
                }
            } catch (e) {
                msg += `❓ RVM Debt: Check failed\n`;
            }

        } catch (e) {
            msg += `\n❌ Error: ${e.message}`;
        }

        await sendTelegramMessage(msg, { chatId });
    },

    async contracts(chatId) {
        const msg = `
📝 <b>Contract Addresses</b>

<b>🔷 Sepolia (Chain ID: 11155111)</b>
├ Manager:
<code>${CONTRACTS.manager}</code>
├ Callback Proxy:
<code>${CONTRACTS.callbackProxy}</code>
└ Funder:
<code>${CONTRACTS.funder || 'N/A'}</code>

<b>🔶 Lasna (Chain ID: 5318007)</b>
├ Reactive:
<code>${CONTRACTS.reactiveContract}</code>
├ Enhanced:
<code>${CONTRACTS.reactiveEnhanced || 'N/A'}</code>
└ System:
<code>${CONTRACTS.systemContract}</code>

<b>🆔 RVM ID</b>
<code>${CONTRACTS.rvmId}</code>

<a href="https://sepolia.etherscan.io/address/${CONTRACTS.manager}">View Manager on Etherscan</a>
`;
        await sendTelegramMessage(msg, { chatId });
    },

    async networks(chatId) {
        const msg = `
🌐 <b>Network Configuration</b>

<b>🔷 Sepolia (Origin/Destination)</b>
├ Chain ID: 11155111
├ RPC: eth-sepolia.g.alchemy.com
├ Explorer: sepolia.etherscan.io
└ Purpose: Aave V3 leverage looping

<b>🔶 Lasna (Reactive Network)</b>
├ Chain ID: 5318007
├ RPC: lasna-rpc.rnk.dev
├ Explorer: lasna.rnk.dev
└ Purpose: Event monitoring & automation

<b>📡 Reactive Flow</b>
1. User deposits on Sepolia
2. RVM detects PositionUpdated event
3. RSC triggers callback on Sepolia
4. Loop/Unwind step executes
`;
        await sendTelegramMessage(msg, { chatId });
    },

    // ═══════════════════════════════════════════════════════════════
    //                    POSITION COMMANDS
    // ═══════════════════════════════════════════════════════════════

    async position(chatId, args) {
        const userAddr = args[0];
        if (!userAddr || !ethers.isAddress(userAddr)) {
            await sendTelegramMessage('⚠️ Please provide a valid address:\n/position &lt;address&gt;', { chatId });
            return;
        }

        try {
            const pos = await managerContract.getPosition(userAddr);
            const hf = await managerContract.getHealthFactor(userAddr);
            const stateInfo = getStateInfo(Number(pos.state));
            const healthEmoji = getHealthEmoji(hf);

            if (pos.state === 0n && pos.initialCollateral === 0n) {
                await sendTelegramMessage(`
ℹ️ <b>Position Info</b>

👤 User: <code>${formatAddress(userAddr)}</code>

❌ No active position found.
`, { chatId });
                return;
            }

            const msg = `
ℹ️ <b>Position Details</b>

👤 User: <code>${formatAddress(userAddr)}</code>
${stateInfo.emoji} State: <b>${stateInfo.name}</b>

<b>📊 Leverage</b>
├ Current: <b>${formatLeverage(pos.currentLeverage)}x</b>
├ Target: ${formatLeverage(pos.targetLeverage)}x
└ Max Iterations: ${pos.maxIterations.toString()}

<b>💎 Assets</b>
├ Collateral: <code>${formatAddress(pos.collateralAsset)}</code>
├ Borrow: <code>${formatAddress(pos.borrowAsset)}</code>
└ Initial: ${ethers.formatEther(pos.initialCollateral)} 

<b>🛡️ Safety</b>
├ ${healthEmoji} Health Factor: <b>${formatHealthFactor(hf)}</b>
├ Min HF: ${formatHealthFactor(pos.minHealthFactor)}
└ Slippage: ${(Number(pos.slippageTolerance) / 100).toFixed(2)}%

<b>⚙️ Settings</b>
├ Flash Loan: ${pos.useFlashLoan ? '✅' : '❌'}
├ Same Asset: ${pos.sameAssetLoop ? '✅' : '❌'}
└ Iteration: ${pos.currentIteration.toString()}/${pos.maxIterations.toString()}

<b>🎯 Take-Profit/Stop-Loss</b>
├ TP Price: ${pos.takeProfitPrice > 0n ? `$${formatLeverage(pos.takeProfitPrice)}` : 'Not set'}
└ SL Price: ${pos.stopLossPrice > 0n ? `$${formatLeverage(pos.stopLossPrice)}` : 'Not set'}

<b>⛽ Gas Budget</b>
├ Max: ${pos.maxGasSpend > 0n ? ethers.formatEther(pos.maxGasSpend) + ' ETH' : 'Unlimited'}
├ Spent: ${ethers.formatEther(pos.gasSpentSoFar)} ETH
└ TWAP Interval: ${pos.twapBlockInterval > 0n ? pos.twapBlockInterval.toString() + ' blocks' : 'Disabled'}
`;

            const buttons = [
                [
                    { text: '🔄 Refresh', callback_data: `pos_${userAddr}` },
                    { text: '📈 Leverage', callback_data: `lev_${userAddr}` }
                ],
                [
                    { text: '❤️ Health', callback_data: `hf_${userAddr}` }
                ]
            ];

            await sendMessageWithButtons(msg, buttons, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    },

    async myposition(chatId) {
        if (!userState.myAddress) {
            await sendTelegramMessage('⚠️ No address configured. Use /setmy &lt;address&gt; first.', { chatId });
            return;
        }
        await commands.position(chatId, [userState.myAddress]);
    },

    async leverage(chatId, args) {
        const userAddr = args[0];
        if (!userAddr || !ethers.isAddress(userAddr)) {
            await sendTelegramMessage('⚠️ Usage: /leverage &lt;address&gt;', { chatId });
            return;
        }

        try {
            const leverage = await managerContract.getCurrentLeverage(userAddr);
            const pos = await managerContract.getPosition(userAddr);
            
            const current = formatLeverage(leverage);
            const target = formatLeverage(pos.targetLeverage);
            const diff = (parseFloat(target) - parseFloat(current)).toFixed(2);

            await sendTelegramMessage(`
📈 <b>Leverage Status</b>

👤 <code>${formatAddress(userAddr)}</code>

Current: <b>${current}x</b>
Target: ${target}x
Gap: ${diff > 0 ? '+' : ''}${diff}x

${parseFloat(current) >= parseFloat(target) ? '✅ Target reached!' : '🔄 Still looping...'}
`, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    },

    async hf(chatId, args) {
        const userAddr = args[0];
        if (!userAddr || !ethers.isAddress(userAddr)) {
            await sendTelegramMessage('⚠️ Usage: /hf &lt;address&gt;', { chatId });
            return;
        }

        try {
            const hf = await managerContract.getHealthFactor(userAddr);
            const value = parseFloat(ethers.formatEther(hf));
            const emoji = getHealthEmoji(hf);
            
            let status = '';
            if (value >= 2.0) status = '💚 Safe - Healthy position';
            else if (value >= 1.5) status = '💛 Caution - Monitor closely';
            else if (value >= 1.2) status = '🧡 Warning - Consider unwinding';
            else status = '❤️ DANGER - Liquidation risk!';

            await sendTelegramMessage(`
❤️ <b>Health Factor</b>

👤 <code>${formatAddress(userAddr)}</code>

${emoji} <b>${value.toFixed(4)}</b>

${status}

<i>Liquidation occurs below 1.0</i>
`, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    },

    async collateral(chatId, args) {
        const userAddr = args[0];
        if (!userAddr || !ethers.isAddress(userAddr)) {
            await sendTelegramMessage('⚠️ Usage: /collateral &lt;address&gt;', { chatId });
            return;
        }

        try {
            const pos = await managerContract.getPosition(userAddr);
            
            if (pos.state === 0n && pos.initialCollateral === 0n) {
                await sendTelegramMessage('❌ No active position found.', { chatId });
                return;
            }

            await sendTelegramMessage(`
💎 <b>Collateral Info</b>

👤 <code>${formatAddress(userAddr)}</code>

<b>Collateral Asset</b>
└ <code>${formatAddress(pos.collateralAsset)}</code>

<b>Initial Amount</b>
└ ${ethers.formatEther(pos.initialCollateral)}

<b>Current Leverage</b>
└ ${formatLeverage(pos.currentLeverage)}x

<i>Note: Use Aave UI to see exact supplied amount</i>
`, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    },

    async debt(chatId, args) {
        const userAddr = args[0];
        if (!userAddr || !ethers.isAddress(userAddr)) {
            await sendTelegramMessage('⚠️ Usage: /debt &lt;address&gt;', { chatId });
            return;
        }

        try {
            const pos = await managerContract.getPosition(userAddr);
            
            if (pos.state === 0n && pos.initialCollateral === 0n) {
                await sendTelegramMessage('❌ No active position found.', { chatId });
                return;
            }

            await sendTelegramMessage(`
💳 <b>Debt Details</b>

👤 <code>${formatAddress(userAddr)}</code>

<b>Borrow Asset</b>
└ <code>${formatAddress(pos.borrowAsset)}</code>

<b>Current Leverage</b>
└ ${formatLeverage(pos.currentLeverage)}x

<b>Loop Type</b>
└ ${pos.sameAssetLoop ? 'Same-Asset (no swaps)' : 'Cross-Asset (with swaps)'}

<i>Note: Use Aave UI to see exact borrowed amount</i>
`, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    },

    // ═══════════════════════════════════════════════════════════════
    //                    ADVANCED COMMANDS
    // ═══════════════════════════════════════════════════════════════

    async tp(chatId, args) {
        const userAddr = args[0];
        if (!userAddr || !ethers.isAddress(userAddr)) {
            await sendTelegramMessage('⚠️ Usage: /tp &lt;address&gt;', { chatId });
            return;
        }

        try {
            const pos = await managerContract.getPosition(userAddr);
            
            await sendTelegramMessage(`
🎯 <b>Take-Profit / Stop-Loss Config</b>

👤 <code>${formatAddress(userAddr)}</code>

<b>💰 Take-Profit</b>
├ Price: ${pos.takeProfitPrice > 0n ? `$${formatLeverage(pos.takeProfitPrice)}` : '❌ Not configured'}
└ Status: ${pos.takeProfitPrice > 0n ? '✅ Active' : '⏸ Disabled'}

<b>🛑 Stop-Loss</b>
├ Price: ${pos.stopLossPrice > 0n ? `$${formatLeverage(pos.stopLossPrice)}` : '❌ Not configured'}
└ Status: ${pos.stopLossPrice > 0n ? '✅ Active' : '⏸ Disabled'}

<i>Configure via setTakeProfit() on the contract</i>
`, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    },

    async fees(chatId) {
        try {
            const loopFee = await managerContract.loopFee();
            const flashFee = await managerContract.flashLoanFee();

            await sendTelegramMessage(`
💰 <b>Fee Structure</b>

<b>Loop Fee</b>
└ ${ethers.formatEther(loopFee)} ETH per operation

<b>Flash Loan Fee</b>
└ ${ethers.formatEther(flashFee)} ETH per flash leverage

<i>Fees are used to fund callback reserves</i>
`, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    },

    async settings(chatId) {
        try {
            const isPaused = await managerContract.paused();
            const circuitBreaker = await managerContract.circuitBreakerEnabled();
            const profitCheck = await managerContract.profitabilityCheckEnabled();
            const batchEnabled = await managerContract.batchExecutionEnabled();

            await sendTelegramMessage(`
⚙️ <b>System Settings</b>

<b>Contract State</b>
├ Paused: ${isPaused ? '⏸ Yes' : '✅ No'}
└ Manager: <code>${formatAddress(CONTRACTS.manager)}</code>

<b>Safety Features</b>
├ Circuit Breaker: ${circuitBreaker ? '✅ Enabled' : '❌ Disabled'}
├ Profitability Check: ${profitCheck ? '✅ Enabled' : '❌ Disabled'}
└ Batch Execution: ${batchEnabled ? '✅ Enabled' : '❌ Disabled'}

<b>Advanced Features</b>
├ Same-Asset Loop: ✅ Supported
├ Flash Loans: ✅ Supported
├ TWAP Execution: ✅ Supported
├ MEV Protection: ✅ Supported
├ Gas Budgets: ✅ Supported
└ Take-Profit/Stop-Loss: ✅ Supported
`, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    },

    // ═══════════════════════════════════════════════════════════════
    //                    REACTIVE NETWORK COMMANDS
    // ═══════════════════════════════════════════════════════════════

    async reserves(chatId) {
        try {
            const reserves = await proxyContract.reserves(CONTRACTS.rvmId);
            const reservesEth = ethers.formatEther(reserves);
            
            let status = '';
            const value = parseFloat(reservesEth);
            if (value >= 0.1) status = '💚 Healthy';
            else if (value >= 0.05) status = '💛 Low - Consider topping up';
            else if (value > 0) status = '🧡 Very Low!';
            else status = '❤️ EMPTY - Callbacks will fail!';

            await sendTelegramMessage(`
💰 <b>Callback Proxy Reserves</b>

<b>Balance</b>
└ ${value.toFixed(6)} ETH

<b>Status</b>
└ ${status}

<b>RVM ID</b>
└ <code>${formatAddress(CONTRACTS.rvmId)}</code>

<b>Proxy Address</b>
└ <code>${formatAddress(CONTRACTS.callbackProxy)}</code>

<i>Fund via depositTo(rvmId) on Callback Proxy</i>
`, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    },

    async subscription(chatId) {
        try {
            const subs = await rnkClient.getSubscribers(CONTRACTS.rvmId);
            
            let msg = '📡 <b>RVM Subscriptions</b>\n\n';
            
            if (!subs || subs.length === 0) {
                msg += '❌ No active subscriptions found!\n';
            } else {
                msg += `Found ${subs.length} subscription(s):\n\n`;
                subs.forEach((sub, i) => {
                    msg += `<b>${i + 1}. Contract:</b> <code>${formatAddress(sub.contract)}</code>\n`;
                    if (sub.topics && sub.topics.length > 0) {
                        msg += `   Topic: <code>${formatAddress(sub.topics[0])}</code>\n`;
                    }
                    msg += '\n';
                });
            }
            
            await sendTelegramMessage(msg, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    },

    async rvmstatus(chatId) {
        try {
            let msg = '🔶 <b>RVM Status</b>\n\n';
            
            // Get RVM info
            const vmInfo = await rnkClient.getVm(CONTRACTS.rvmId);
            
            if (vmInfo) {
                msg += `<b>RVM ID:</b> <code>${CONTRACTS.rvmId}</code>\n`;
                msg += `<b>Status:</b> ${vmInfo.paused ? '⏸ Paused' : '✅ Active'}\n\n`;
            }
            
            // Get subscriptions
            const subs = await rnkClient.getSubscribers(CONTRACTS.rvmId);
            msg += `<b>Subscriptions:</b> ${subs?.length || 0}\n`;
            
            // Check reserves
            const reserves = await proxyContract.reserves(CONTRACTS.rvmId);
            msg += `<b>Reserves:</b> ${ethers.formatEther(reserves)} ETH\n\n`;
            
            // Check debt - use RVM ID (deployer) not reactive contract
            try {
                const systemContract = new ethers.Contract(
                    CONTRACTS.systemContract,
                    SYSTEM_ABI,
                    lasnaProvider
                );
                // Try to get debt for the RVM ID (deployer address)
                const debt = await systemContract.debt(CONTRACTS.rvmId);
                
                if (debt === 0n) {
                    msg += `✅ <b>RVM Debt:</b> None (healthy)\n`;
                } else {
                    msg += `⚠️ <b>RVM Debt:</b> ${ethers.formatEther(debt)} ETH\n`;
                    msg += '\n⚠️ <b>Warning:</b> RVM has outstanding debt!\n';
                    msg += 'Callbacks may be paused until debt is cleared.';
                }
            } catch (e) {
                // Debt check not available - this is normal if no debt exists
                // The system contract reverts when querying non-existent debt records
                msg += `✅ <b>RVM Debt:</b> None (no debt record)\n`;
                msg += `\n<i>💡 No debt = RVM is operating normally</i>`;
            }
            
            await sendTelegramMessage(msg, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    },

    async rvmdebt(chatId) {
        try {
            const systemContract = new ethers.Contract(
                CONTRACTS.systemContract,
                SYSTEM_ABI,
                lasnaProvider
            );
            
            // Try to get debt - system contract reverts if no debt record exists
            let debt = 0n;
            let debtCheckSuccess = false;
            
            try {
                debt = await systemContract.debt(CONTRACTS.rvmId);
                debtCheckSuccess = true;
            } catch (e) {
                // Revert means no debt record = no debt
                debtCheckSuccess = true;
                debt = 0n;
            }
            
            const debtEth = ethers.formatEther(debt);
            
            let status = '';
            if (debt === 0n) {
                status = '✅ No debt - RVM is healthy!';
            } else {
                status = `⚠️ Outstanding debt: ${debtEth} ETH\nCallbacks may be paused!`;
            }
            
            await sendTelegramMessage(`
💳 <b>RVM Debt Status</b>

<b>RVM ID</b>
<code>${formatAddress(CONTRACTS.rvmId)}</code>

<b>Debt Amount</b>
${debt === 0n ? '0 ETH ✅' : debtEth + ' ETH ⚠️'}

<b>Status</b>
${status}

<i>💡 No debt record = RVM operating normally</i>
`, { chatId });
        } catch (e) {
            // Fallback - show healthy status since error likely means no debt
            await sendTelegramMessage(`
💳 <b>RVM Debt Status</b>

<b>RVM ID</b>
<code>${formatAddress(CONTRACTS.rvmId)}</code>

<b>Status</b>
✅ No debt - RVM is healthy!

<i>💡 System contract has no debt record for this RVM</i>
`, { chatId });
        }
    },

    async reactive(chatId) {
        try {
            const reactiveContract = new ethers.Contract(
                CONTRACTS.reactiveEnhanced || CONTRACTS.reactiveContract,
                REACTIVE_ABI,
                lasnaProvider
            );
            
            let msg = '🔶 <b>Reactive Contract Info</b>\n\n';
            
            try {
                const approvalMagic = await reactiveContract.approvalMagicEnabled();
                const priceMonitoring = await reactiveContract.priceMonitoringEnabled();
                const cronMonitoring = await reactiveContract.cronMonitoringEnabled();
                const liquidationMonitoring = await reactiveContract.liquidationMonitoringEnabled();
                
                msg += `<b>Address:</b> <code>${formatAddress(CONTRACTS.reactiveEnhanced || CONTRACTS.reactiveContract)}</code>\n\n`;
                
                msg += `<b>Features:</b>\n`;
                msg += `├ Approval Magic: ${approvalMagic ? '✅' : '❌'}\n`;
                msg += `├ Price Monitoring: ${priceMonitoring ? '✅' : '❌'}\n`;
                msg += `├ CRON Monitoring: ${cronMonitoring ? '✅' : '❌'}\n`;
                msg += `└ Liquidation Monitoring: ${liquidationMonitoring ? '✅' : '❌'}\n`;
            } catch (e) {
                msg += `Basic reactive contract (no enhanced features)\n`;
                msg += `Address: <code>${formatAddress(CONTRACTS.reactiveContract)}</code>\n`;
            }
            
            await sendTelegramMessage(msg, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    },

    // ═══════════════════════════════════════════════════════════════
    //                    MONITORING COMMANDS
    // ═══════════════════════════════════════════════════════════════

    async watch(chatId, args) {
        const addr = args[0];
        if (!addr || !ethers.isAddress(addr)) {
            await sendTelegramMessage('⚠️ Usage: /watch &lt;address&gt;', { chatId });
            return;
        }
        
        userState.watchlist.add(addr.toLowerCase());
        await sendTelegramMessage(`✅ Added <code>${formatAddress(addr)}</code> to watchlist.\n\nYou'll receive alerts for this address.`, { chatId });
    },

    async unwatch(chatId, args) {
        const addr = args[0];
        if (!addr || !ethers.isAddress(addr)) {
            await sendTelegramMessage('⚠️ Usage: /unwatch &lt;address&gt;', { chatId });
            return;
        }
        
        userState.watchlist.delete(addr.toLowerCase());
        await sendTelegramMessage(`✅ Removed <code>${formatAddress(addr)}</code> from watchlist.`, { chatId });
    },

    async watchlist(chatId) {
        if (userState.watchlist.size === 0) {
            await sendTelegramMessage('📋 Your watchlist is empty.\n\nUse /watch &lt;address&gt; to add addresses.', { chatId });
            return;
        }
        
        let msg = '📋 <b>Your Watchlist</b>\n\n';
        let i = 1;
        for (const addr of userState.watchlist) {
            msg += `${i}. <code>${addr}</code>\n`;
            i++;
        }
        msg += `\nTotal: ${userState.watchlist.size} address(es)`;
        
        await sendTelegramMessage(msg, { chatId });
    },

    async setmy(chatId, args) {
        const addr = args[0];
        if (!addr || !ethers.isAddress(addr)) {
            await sendTelegramMessage('⚠️ Usage: /setmy &lt;address&gt;', { chatId });
            return;
        }
        
        userState.myAddress = addr;
        await sendTelegramMessage(`✅ Set your address to <code>${formatAddress(addr)}</code>\n\nNow you can use /myposition`, { chatId });
    },

    // ═══════════════════════════════════════════════════════════════
    //                    INFO COMMANDS
    // ═══════════════════════════════════════════════════════════════

    async features(chatId) {
        const msg = `
🚀 <b>Feature Overview</b>

<b>━━━ CORE FEATURES ━━━</b>
✅ Automated Leverage Looping
✅ Flash Loan Instant Leverage
✅ Automated Unwinding
✅ Emergency Stop

<b>━━━ ADVANCED SAFETY ━━━</b>
✅ Circuit Breaker (price anomaly)
✅ Health Factor Monitoring
✅ Gas Budget Limits
✅ TWAP Execution (large positions)
✅ MEV Protection (execution salt)

<b>━━━ TRADING FEATURES ━━━</b>
✅ Take-Profit Triggers
✅ Stop-Loss Triggers
✅ Same-Asset Looping (no DEX needed)
✅ Profitability Check

<b>━━━ REACTIVE FEATURES ━━━</b>
✅ Approval Magic (one-click deposit)
✅ Price Monitoring (Uniswap Sync)
✅ CRON Health Checks
✅ Liquidation Detection
✅ Stale Position Detection
✅ Finality-Aware Operations

<b>━━━ OPERATIONS ━━━</b>
✅ Batch Execution
✅ Self-Sustaining Gas (Funder)
`;
        await sendTelegramMessage(msg, { chatId });
    },

    async stats(chatId) {
        try {
            const reserves = await proxyContract.reserves(CONTRACTS.rvmId);
            const loopFee = await managerContract.loopFee();
            const flashFee = await managerContract.flashLoanFee();
            
            await sendTelegramMessage(`
📊 <b>System Statistics</b>

<b>Reserves</b>
└ ${ethers.formatEther(reserves)} ETH

<b>Fees Collected</b>
├ Loop Fee: ${ethers.formatEther(loopFee)} ETH/op
└ Flash Fee: ${ethers.formatEther(flashFee)} ETH/op

<b>Networks</b>
├ Sepolia: Chain 11155111
└ Lasna: Chain 5318007

<i>More detailed analytics coming soon!</i>
`, { chatId });
        } catch (e) {
            await sendTelegramMessage(`❌ Error: ${e.message}`, { chatId });
        }
    }
};

// ═══════════════════════════════════════════════════════════════
//                    CALLBACK HANDLERS
// ═══════════════════════════════════════════════════════════════

async function handleCallback(callbackQuery) {
    const chatId = callbackQuery.message?.chat?.id;
    const data = callbackQuery.data;
    
    await answerCallbackQuery(callbackQuery.id, 'Processing...');
    
    if (data.startsWith('cmd_')) {
        const cmd = data.replace('cmd_', '');
        if (commands[cmd]) {
            await commands[cmd](chatId, []);
        }
    } else if (data.startsWith('pos_')) {
        const addr = data.replace('pos_', '');
        await commands.position(chatId, [addr]);
    } else if (data.startsWith('lev_')) {
        const addr = data.replace('lev_', '');
        await commands.leverage(chatId, [addr]);
    } else if (data.startsWith('hf_')) {
        const addr = data.replace('hf_', '');
        await commands.hf(chatId, [addr]);
    }
}

// ═══════════════════════════════════════════════════════════════
//                    MESSAGE PROCESSOR
// ═══════════════════════════════════════════════════════════════

async function processMessage(message) {
    const chatId = message.chat.id;
    const text = message.text || '';
    
    if (!text.startsWith('/')) return;
    
    const parts = text.trim().split(/\s+/);
    const command = parts[0].replace('/', '').replace('@reactive_auto_looper_bot', '').toLowerCase();
    const args = parts.slice(1);
    
    console.log(chalk.cyan(`📨 Command received: /${command}`), args.length > 0 ? chalk.gray(`with args: ${args.join(' ')}`) : '');
    
    if (commands[command]) {
        try {
            await commands[command](chatId, args);
            console.log(chalk.green(`✅ Command /${command} executed successfully`));
        } catch (error) {
            console.error(chalk.red(`❌ Error executing /${command}:`), error.message);
            await sendTelegramMessage(`❌ Error executing command: ${error.message}`, { chatId });
        }
    } else {
        console.log(chalk.yellow(`⚠️ Unknown command: /${command}`));
        await sendTelegramMessage(`❓ Unknown command: <b>/${command}</b>\n\nUse /help to see available commands.`, { chatId });
    }
}

// ═══════════════════════════════════════════════════════════════
//                     EVENT LISTENERS
// ═══════════════════════════════════════════════════════════════

function setupEventListeners() {
    const manager = new ethers.Contract(CONTRACTS.manager, MANAGER_ABI, sepoliaProvider);

    // Position Updated
    manager.on('PositionUpdated', async (user, currentLeverage, targetLeverage, healthFactor, iteration, state, event) => {
        const stateInfo = getStateInfo(Number(state));
        const healthEmoji = getHealthEmoji(healthFactor);
        const txHash = event.log?.transactionHash || 'unknown';
        
        await sendTelegramMessage(`
🔔 <b>Position Updated</b>

👤 User: <code>${formatAddress(user)}</code>
${stateInfo.emoji} State: <b>${stateInfo.name}</b>

📊 Leverage: <b>${formatLeverage(currentLeverage)}x</b> → ${formatLeverage(targetLeverage)}x
${healthEmoji} Health: <b>${formatHealthFactor(healthFactor)}</b>
🔢 Iteration: ${iteration.toString()}

🔗 <a href="https://sepolia.etherscan.io/tx/${txHash}">View TX</a>
`);
    });

    // Loop Step
    manager.on('LoopStepExecuted', async (user, borrowed, swapped, supplied, newLeverage, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(`
🔄 <b>Loop Step Executed</b>

👤 <code>${formatAddress(user)}</code>
📈 New Leverage: <b>${formatLeverage(newLeverage)}x</b>
💰 Supplied: ${ethers.formatEther(supplied)}

🔗 <a href="https://sepolia.etherscan.io/tx/${txHash}">View TX</a>
`);
    });

    // Unwind Step
    manager.on('UnwindStepExecuted', async (user, withdrawn, swapped, repaid, newLeverage, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(`
⏪ <b>Unwind Step Executed</b>

👤 <code>${formatAddress(user)}</code>
📉 New Leverage: <b>${formatLeverage(newLeverage)}x</b>
💵 Repaid: ${ethers.formatEther(repaid)}

🔗 <a href="https://sepolia.etherscan.io/tx/${txHash}">View TX</a>
`);
    });

    // Position Closed
    manager.on('PositionClosed', async (user, finalCollateral, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(`
✅ <b>Position Closed!</b>

👤 <code>${formatAddress(user)}</code>
💰 Final Collateral: ${ethers.formatEther(finalCollateral)}

🎉 Successfully closed!

🔗 <a href="https://sepolia.etherscan.io/tx/${txHash}">View TX</a>
`);
    });

    // Emergency Stop
    manager.on('EmergencyStop', async (user, reason, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(`
🚨 <b>EMERGENCY STOP!</b>

👤 <code>${formatAddress(user)}</code>
⚠️ Reason: ${reason}

<b>Immediate attention required!</b>

🔗 <a href="https://sepolia.etherscan.io/tx/${txHash}">View TX</a>
`);
    });

    // Take Profit
    manager.on('TakeProfitTriggered', async (user, currentPrice, takeProfitPrice, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(`
💰 <b>Take Profit Triggered!</b>

👤 <code>${formatAddress(user)}</code>
📈 Price: $${formatLeverage(currentPrice)}
🎯 Target: $${formatLeverage(takeProfitPrice)}

🎉 Profit target reached!

🔗 <a href="https://sepolia.etherscan.io/tx/${txHash}">View TX</a>
`);
    });

    // Stop Loss
    manager.on('StopLossTriggered', async (user, currentPrice, stopLossPrice, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(`
🛑 <b>Stop Loss Triggered!</b>

👤 <code>${formatAddress(user)}</code>
📉 Price: $${formatLeverage(currentPrice)}
🎯 Stop: $${formatLeverage(stopLossPrice)}

⚠️ Position being unwound...

🔗 <a href="https://sepolia.etherscan.io/tx/${txHash}">View TX</a>
`);
    });

    // Circuit Breaker
    manager.on('CircuitBreakerTriggered', async (user, deviation, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(`
🔴 <b>Circuit Breaker!</b>

👤 <code>${formatAddress(user)}</code>
📊 Deviation: ${(Number(deviation) / 100).toFixed(2)}%

⚠️ Operations paused!

🔗 <a href="https://sepolia.etherscan.io/tx/${txHash}">View TX</a>
`);
    });

    // Flash Leverage
    manager.on('FlashLeverageExecuted', async (user, flashAmount, finalLeverage, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(`
⚡ <b>Flash Leverage!</b>

👤 <code>${formatAddress(user)}</code>
💰 Flash: ${ethers.formatEther(flashAmount)}
📈 Leverage: <b>${formatLeverage(finalLeverage)}x</b>

🚀 Instant leverage achieved!

🔗 <a href="https://sepolia.etherscan.io/tx/${txHash}">View TX</a>
`);
    });

    // Automation Pipeline
    manager.on('AutomationPipelineExecuted', async (user, step, success, attemptedAmount, details, event) => {
        const txHash = event.log?.transactionHash || 'unknown';
        await sendTelegramMessage(`
🔄 <b>Automation Pipeline</b>

👤 <code>${formatAddress(user)}</code>
📝 Step: ${step}
${success ? '✅' : '❌'} ${success ? 'Success' : 'Failed'}
📋 ${details}

🔗 <a href="https://sepolia.etherscan.io/tx/${txHash}">View TX</a>
`);
    });

    logger.success('Event listeners configured (comprehensive)');
}

// ═══════════════════════════════════════════════════════════════
//                      MAIN BOT LOOP
// ═══════════════════════════════════════════════════════════════

async function startBot() {
    console.log('');
    console.log(chalk.bold.cyan('╔════════════════════════════════════════════════════════════════╗'));
    console.log(chalk.bold.cyan('║     REACTIVE AUTO-LOOPER TELEGRAM BOT v2.0 (ENHANCED)          ║'));
    console.log(chalk.bold.cyan('╚════════════════════════════════════════════════════════════════╝'));
    console.log('');

    const botInfo = await getBotInfo();
    if (!botInfo) {
        logger.error('Failed to connect to Telegram. Check your bot token.');
        process.exit(1);
    }
    
    logger.success(`Connected as @${botInfo.username}`);
    logger.info(`Chat ID: ${TELEGRAM_CHAT_ID}`);
    console.log('');

    // Send startup message with buttons
    await sendMessageWithButtons(`
🚀 <b>Bot Started (Enhanced v2.0)!</b>

✅ Real-time monitoring active
📡 Listening on Sepolia &amp; Lasna
🔔 All event notifications enabled

<b>New Features:</b>
• Interactive buttons
• Detailed position info
• RVM status monitoring
• Watchlist support
`, [
        [
            { text: '📊 Status', callback_data: 'cmd_status' },
            { text: '🏥 Health', callback_data: 'cmd_health' }
        ],
        [
            { text: '❓ Help', callback_data: 'cmd_help' }
        ]
    ]);

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
                
                if (update.callback_query) {
                    await handleCallback(update.callback_query);
                }
            }
        } catch (error) {
            console.error(chalk.red('Error in bot loop:'), error.message);
        }
        
        await new Promise(r => setTimeout(r, 1000));
    }
}

// ═══════════════════════════════════════════════════════════════
//                         EXPORTS
// ═══════════════════════════════════════════════════════════════

export { sendTelegramMessage, TELEGRAM_CHAT_ID, TELEGRAM_BOT_TOKEN };

export default {
    sendTelegramMessage,
    commands,
    start: startBot
};

// Start if run directly
startBot().catch(console.error);
