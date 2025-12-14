#!/usr/bin/env node

/**
 * Real-time Event Watcher for Reactive Auto-Looper
 * 
 * Monitors events from:
 * - Sepolia: AutoLooperManager (PositionUpdated, LoopStepExecuted, etc.)
 * - Lasna RVM: react() calls and Callback events
 * 
 * Usage: node watch-events.js [--user <address>]
 */

import { ethers } from 'ethers';
import chalk from 'chalk';
import boxen from 'boxen';
import { NETWORKS, CONTRACTS, TOPICS, ABIS, POSITION_STATES } from './config.js';
import logger from './logger.js';
import RnkClient from './rnk-client.js';

// ═══════════════════════════════════════════════════════════════
//                         CONFIGURATION
// ═══════════════════════════════════════════════════════════════

const POLL_INTERVAL = 3000; // 3 seconds for RVM polling
let userFilter = null;

// Parse command line args
const args = process.argv.slice(2);
const userIdx = args.indexOf('--user');
if (userIdx !== -1 && args[userIdx + 1]) {
    userFilter = args[userIdx + 1].toLowerCase();
    logger.info(`Filtering events for user: ${userFilter}`);
}

// ═══════════════════════════════════════════════════════════════
//                         PROVIDERS
// ═══════════════════════════════════════════════════════════════

const sepoliaProvider = new ethers.JsonRpcProvider(NETWORKS.sepolia.rpc);
const lasnaProvider = new ethers.JsonRpcProvider(NETWORKS.lasna.rpc);
const rnkClient = new RnkClient();

// ═══════════════════════════════════════════════════════════════
//                      EVENT DECODERS
// ═══════════════════════════════════════════════════════════════

const managerInterface = new ethers.Interface(ABIS.manager);
const reactiveInterface = new ethers.Interface(ABIS.reactive);

function decodePositionUpdated(log) {
    try {
        const decoded = managerInterface.parseLog({
            topics: log.topics,
            data: log.data
        });
        return {
            user: decoded.args[0],
            currentLeverage: decoded.args[1].toString(),
            targetLeverage: decoded.args[2].toString(),
            healthFactor: decoded.args[3].toString(),
            iteration: decoded.args[4].toString(),
            state: Number(decoded.args[5])
        };
    } catch (e) {
        return null;
    }
}

function decodeCallback(log) {
    try {
        // Callback event: (uint256 indexed chain_id, address indexed _contract, uint64 indexed gas_limit, bytes payload)
        const chainId = BigInt(log.topics[1]).toString();
        const contract = '0x' + log.topics[2].slice(-40);
        const gasLimit = BigInt(log.topics[3]).toString();
        
        // Decode payload from data
        const abiCoder = new ethers.AbiCoder();
        const [payload] = abiCoder.decode(['bytes'], log.data);
        
        // Get function selector
        const selector = payload.slice(0, 10);
        
        return {
            chainId,
            contract,
            gasLimit,
            selector,
            payload: payload.slice(0, 74) + '...'
        };
    } catch (e) {
        return null;
    }
}

// ═══════════════════════════════════════════════════════════════
//                    SEPOLIA EVENT HANDLERS
// ═══════════════════════════════════════════════════════════════

async function handleSepoliaLog(log) {
    const topic0 = log.topics[0];
    
    // PositionUpdated
    if (topic0 === TOPICS.PositionUpdated) {
        const data = decodePositionUpdated(log);
        if (!data) return;
        
        // Apply user filter
        if (userFilter && data.user.toLowerCase() !== userFilter) return;
        
        const stateInfo = POSITION_STATES[data.state] || { name: 'UNKNOWN', emoji: '❓' };
        
        console.log('');
        console.log(boxen(
            chalk.bold.cyan('📡 POSITION UPDATED') + '\n\n' +
            chalk.white(`User: ${data.user}\n`) +
            chalk.white(`Current: ${logger.formatLeverage(data.currentLeverage)} → Target: ${logger.formatLeverage(data.targetLeverage)}\n`) +
            chalk.white(`Health: ${(Number(data.healthFactor) / 1e18).toFixed(2)}\n`) +
            chalk.white(`Iteration: ${data.iteration}\n`) +
            chalk.white(`State: ${stateInfo.emoji} ${stateInfo.name}`),
            { padding: 1, borderColor: 'cyan', borderStyle: 'round', title: 'SEPOLIA', titleAlignment: 'center' }
        ));
        console.log('');
        
        logger.info(`Block ${log.blockNumber} | TX: ${logger.truncateAddress(log.transactionHash)}`, null, 'sepolia');
        
        // Check if this should trigger RVM
        if (data.state === 1 || data.state === 2) {
            logger.warn('⏳ Waiting for RVM to process this event...', null, 'sepolia');
        }
    }
    
    // LoopStepExecuted
    if (topic0 === TOPICS.LoopStepExecuted) {
        console.log('');
        console.log(chalk.bgGreen.black(' 🔄 LOOP STEP EXECUTED '));
        logger.success('Loop step completed on Sepolia!', null, 'sepolia');
        console.log('');
    }
}

// ═══════════════════════════════════════════════════════════════
//                    RVM TRANSACTION HANDLER
// ═══════════════════════════════════════════════════════════════

let lastRvmTxNumber = 0;

async function checkRvmTransactions() {
    try {
        const headNumber = await rnkClient.getHeadNumber(CONTRACTS.rvmId);
        const currentTxNumber = parseInt(headNumber, 16);
        
        if (currentTxNumber > lastRvmTxNumber) {
            // New transactions!
            const fromHex = '0x' + (lastRvmTxNumber + 1).toString(16);
            const limitHex = '0x' + Math.min(currentTxNumber - lastRvmTxNumber, 50).toString(16);
            
            const txs = await rnkClient.getTransactions(CONTRACTS.rvmId, fromHex, limitHex);
            
            for (const tx of txs || []) {
                await handleRvmTransaction(tx);
            }
            
            lastRvmTxNumber = currentTxNumber;
        }
    } catch (error) {
        // Silently retry on errors
    }
}

async function handleRvmTransaction(tx) {
    const txNumber = parseInt(tx.number, 16);
    const isSuccess = tx.status === 1;
    const isReact = tx.data?.startsWith('0x0d152c2c'); // react() selector
    
    if (tx.createContract) {
        logger.info(`RVM TX #${txNumber}: Contract deployment`, null, 'rvm');
        return;
    }
    
    if (!isReact) return;
    
    // This is a react() call
    console.log('');
    console.log(boxen(
        chalk.bold.magenta('⚡ RVM REACT() CALLED') + '\n\n' +
        chalk.white(`TX #: ${txNumber}\n`) +
        chalk.white(`Status: ${isSuccess ? '✅ Success' : '❌ Failed'}\n`) +
        chalk.white(`Gas Used: ${tx.used}\n`) +
        chalk.white(`Ref Chain: ${tx.refChainId}\n`) +
        chalk.white(`Ref TX: ${logger.truncateAddress(tx.refTx)}`),
        { padding: 1, borderColor: 'magenta', borderStyle: 'round', title: 'RVM', titleAlignment: 'center' }
    ));
    console.log('');
    
    // Get transaction logs to check for Callback event
    try {
        const logs = await rnkClient.getTransactionLogs(CONTRACTS.rvmId, tx.number);
        
        for (const log of logs || []) {
            if (log.topics[0] === TOPICS.Callback) {
                const callbackData = decodeCallback(log);
                if (callbackData) {
                    console.log(chalk.yellow(`  📤 CALLBACK EMITTED`));
                    console.log(chalk.yellow(`     Chain: ${callbackData.chainId}`));
                    console.log(chalk.yellow(`     Target: ${callbackData.contract}`));
                    console.log(chalk.yellow(`     Selector: ${callbackData.selector}`));
                    console.log('');
                    
                    // Check if callback was delivered
                    logger.warn('⏳ Callback emitted, checking delivery to Sepolia...', null, 'rvm');
                }
            }
            
            if (log.topics[0] === TOPICS.LoopCallbackTriggered) {
                logger.success('Loop callback triggered!', null, 'rvm');
            }
        }
    } catch (e) {
        // Ignore log fetch errors
    }
}

// ═══════════════════════════════════════════════════════════════
//                         MAIN WATCHER
// ═══════════════════════════════════════════════════════════════

async function startWatching() {
    console.log('');
    console.log(boxen(
        chalk.bold.white('🔍 REACTIVE AUTO-LOOPER MONITOR') + '\n\n' +
        chalk.gray('Watching for events on:\n') +
        chalk.cyan('  • Sepolia: Manager events\n') +
        chalk.magenta('  • Lasna RVM: react() calls\n') +
        chalk.gray(`\nContracts:\n`) +
        chalk.white(`  Manager: ${logger.truncateAddress(CONTRACTS.manager)}\n`) +
        chalk.white(`  Reactive: ${logger.truncateAddress(CONTRACTS.reactiveContract)}\n`) +
        chalk.white(`  RVM ID: ${logger.truncateAddress(CONTRACTS.rvmId)}`),
        { padding: 1, borderColor: 'blue', borderStyle: 'double', title: 'MONITOR STARTED', titleAlignment: 'center' }
    ));
    console.log('');
    
    // Initialize RVM tx counter
    try {
        const headNumber = await rnkClient.getHeadNumber(CONTRACTS.rvmId);
        lastRvmTxNumber = parseInt(headNumber, 16);
        logger.info(`RVM has ${lastRvmTxNumber} transactions`, null, 'rvm');
    } catch (e) {
        logger.warn('Could not get initial RVM state', null, 'rvm');
    }
    
    // Set up Sepolia event listener
    const filter = {
        address: CONTRACTS.manager,
        topics: [[TOPICS.PositionUpdated, TOPICS.LoopStepExecuted]]
    };
    
    sepoliaProvider.on(filter, handleSepoliaLog);
    logger.success('Listening for Sepolia events...', null, 'sepolia');
    
    // Start RVM polling
    setInterval(checkRvmTransactions, POLL_INTERVAL);
    logger.success(`Polling RVM every ${POLL_INTERVAL/1000}s...`, null, 'rvm');
    
    console.log('');
    logger.separator();
    console.log(chalk.gray('Waiting for events... (Press Ctrl+C to stop)'));
    logger.separator();
    console.log('');
}

// Handle shutdown
process.on('SIGINT', () => {
    console.log('');
    logger.info('Shutting down monitor...');
    process.exit(0);
});

// Start
startWatching().catch(console.error);
