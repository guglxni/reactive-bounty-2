#!/usr/bin/env node

/**
 * RVM Debug Tool for Reactive Auto-Looper
 * 
 * Deep inspection of RVM state, transactions, and logs
 * 
 * Usage: 
 *   node debug-rvm.js                    # Full debug info
 *   node debug-rvm.js --tx <number>      # Debug specific transaction
 *   node debug-rvm.js --logs <number>    # Get logs for transaction
 */

import { ethers } from 'ethers';
import chalk from 'chalk';
import boxen from 'boxen';
import Table from 'cli-table3';
import { NETWORKS, CONTRACTS, TOPICS, ABIS } from './config.js';
import logger from './logger.js';
import RnkClient from './rnk-client.js';

const rnkClient = new RnkClient();

// ═══════════════════════════════════════════════════════════════
//                         PARSE ARGS
// ═══════════════════════════════════════════════════════════════

const args = process.argv.slice(2);
const txIdx = args.indexOf('--tx');
const logsIdx = args.indexOf('--logs');

const specificTx = txIdx !== -1 ? args[txIdx + 1] : null;
const logsForTx = logsIdx !== -1 ? args[logsIdx + 1] : null;

// ═══════════════════════════════════════════════════════════════
//                      DEBUG FUNCTIONS
// ═══════════════════════════════════════════════════════════════

async function debugRvmState() {
    console.log('');
    console.log(chalk.bold.magenta('═══════════════════════════════════════════════════════════════'));
    console.log(chalk.bold.magenta('                    RVM DEBUG INFORMATION'));
    console.log(chalk.bold.magenta('═══════════════════════════════════════════════════════════════'));
    console.log('');

    // Get RVM mapping
    console.log(chalk.yellow('📍 RVM Address Mapping'));
    console.log(chalk.gray('─'.repeat(50)));
    
    try {
        const mapping = await rnkClient.getRnkAddressMapping(CONTRACTS.reactiveContract);
        console.log(`  Contract: ${chalk.white(CONTRACTS.reactiveContract)}`);
        console.log(`  RVM ID:   ${chalk.green(mapping.rvmId)}`);
        
        if (mapping.rvmId.toLowerCase() !== CONTRACTS.rvmId.toLowerCase()) {
            console.log(chalk.red(`  ⚠️  WARNING: RVM ID mismatch!`));
            console.log(chalk.red(`     Expected: ${CONTRACTS.rvmId}`));
            console.log(chalk.red(`     Actual:   ${mapping.rvmId}`));
        }
    } catch (e) {
        console.log(chalk.red(`  Error: ${e.message}`));
    }
    
    console.log('');

    // Get VM info
    console.log(chalk.yellow('⚡ RVM Instance Info'));
    console.log(chalk.gray('─'.repeat(50)));
    
    try {
        const vm = await rnkClient.getVm(CONTRACTS.rvmId);
        console.log(`  RVM ID:         ${chalk.white(vm.rvmId)}`);
        console.log(`  Last TX #:      ${chalk.white(parseInt(vm.lastTxNumber, 16))}`);
        console.log(`  Contracts:      ${chalk.white(vm.contracts)}`);
    } catch (e) {
        console.log(chalk.red(`  Error: ${e.message}`));
    }
    
    console.log('');

    // Get subscriptions
    console.log(chalk.yellow('🔔 Active Subscriptions'));
    console.log(chalk.gray('─'.repeat(50)));
    
    try {
        const subs = await rnkClient.getSubscribers(CONTRACTS.rvmId);
        
        if (subs && subs.length > 0) {
            const subTable = new Table({
                head: ['Chain', 'Contract', 'Topic 0'],
                style: { head: ['yellow'] },
                colWidths: [10, 45, 45]
            });
            
            for (const sub of subs) {
                subTable.push([
                    sub.chainId,
                    sub.contract,
                    sub.topics[0] ? logger.truncateAddress(sub.topics[0], 15) : 'ANY'
                ]);
            }
            
            console.log(subTable.toString());
        } else {
            console.log(chalk.gray('  No subscriptions found'));
        }
    } catch (e) {
        console.log(chalk.red(`  Error: ${e.message}`));
    }
    
    console.log('');
}

async function debugTransaction(txNumber) {
    console.log('');
    console.log(chalk.cyan(`📋 Debug Transaction #${txNumber}`));
    console.log(chalk.gray('─'.repeat(50)));
    
    const txHex = '0x' + parseInt(txNumber).toString(16);
    
    try {
        const txs = await rnkClient.getTransactions(CONTRACTS.rvmId, txHex, '0x1');
        
        if (!txs || txs.length === 0) {
            console.log(chalk.red('  Transaction not found'));
            return;
        }
        
        const tx = txs[0];
        
        console.log(`  Hash:           ${chalk.white(tx.hash)}`);
        console.log(`  Number:         ${chalk.white(parseInt(tx.number, 16))}`);
        console.log(`  Status:         ${tx.status === 1 ? chalk.green('✅ Success') : chalk.red('❌ Failed')}`);
        console.log(`  Time:           ${chalk.white(new Date(tx.time * 1000).toISOString())}`);
        console.log(`  From:           ${chalk.white(tx.from)}`);
        console.log(`  To:             ${chalk.white(tx.to)}`);
        console.log(`  Gas Limit:      ${chalk.white(tx.limit)}`);
        console.log(`  Gas Used:       ${chalk.white(tx.used)}`);
        console.log(`  Create:         ${chalk.white(tx.createContract)}`);
        console.log(`  Ref Chain:      ${chalk.white(tx.refChainId)}`);
        console.log(`  Ref TX:         ${chalk.white(tx.refTx)}`);
        console.log(`  Ref Event Idx:  ${chalk.white(tx.refEventIndex)}`);
        
        // Decode function selector
        if (tx.data && tx.data.length >= 10) {
            const selector = tx.data.slice(0, 10);
            let funcName = 'Unknown';
            
            if (selector === '0x0d152c2c') funcName = 'react(LogRecord)';
            else if (tx.createContract) funcName = 'Constructor';
            
            console.log(`  Function:       ${chalk.yellow(funcName)} (${selector})`);
        }
        
        console.log('');
        console.log(chalk.gray('  Data (first 200 chars):'));
        console.log(chalk.gray(`  ${tx.data?.slice(0, 200)}...`));
        
    } catch (e) {
        console.log(chalk.red(`  Error: ${e.message}`));
    }
    
    console.log('');
}

async function debugTransactionLogs(txNumber) {
    console.log('');
    console.log(chalk.green(`📜 Logs for Transaction #${txNumber}`));
    console.log(chalk.gray('─'.repeat(50)));
    
    const txHex = '0x' + parseInt(txNumber).toString(16);
    
    try {
        const logs = await rnkClient.getTransactionLogs(CONTRACTS.rvmId, txHex);
        
        if (!logs || logs.length === 0) {
            console.log(chalk.gray('  No logs found'));
            return;
        }
        
        for (let i = 0; i < logs.length; i++) {
            const log = logs[i];
            
            console.log(`\n  ${chalk.bold(`Log #${i}`)}`);
            console.log(`  Address: ${chalk.white(log.address)}`);
            
            // Identify known events
            const topic0 = log.topics[0];
            let eventName = 'Unknown';
            
            if (topic0 === TOPICS.Callback) eventName = '📤 Callback';
            else if (topic0 === TOPICS.LoopCallbackTriggered) eventName = '🔄 LoopCallbackTriggered';
            else if (topic0 === TOPICS.UnwindCallbackTriggered) eventName = '⏪ UnwindCallbackTriggered';
            else if (topic0 === TOPICS.Subscribe) eventName = '🔔 Subscribe';
            
            console.log(`  Event:   ${chalk.yellow(eventName)}`);
            
            console.log(`  Topics:`);
            for (let j = 0; j < log.topics.length; j++) {
                const topic = log.topics[j];
                let decoded = '';
                
                // Try to decode indexed parameters
                if (j === 0) decoded = '(event signature)';
                else if (topic && topic !== '0x' + '0'.repeat(64)) {
                    // Check if it looks like an address
                    if (topic.startsWith('0x000000000000000000000000')) {
                        decoded = `(address: 0x${topic.slice(-40)})`;
                    } else {
                        // Try as uint256
                        try {
                            const val = BigInt(topic);
                            if (val < 1000000n) decoded = `(uint: ${val})`;
                        } catch {}
                    }
                }
                
                console.log(`    [${j}]: ${chalk.gray(topic)} ${chalk.cyan(decoded)}`);
            }
            
            console.log(`  Data:    ${chalk.gray(log.data?.slice(0, 100))}...`);
            
            // Special decoding for Callback event
            if (topic0 === TOPICS.Callback) {
                try {
                    const chainId = BigInt(log.topics[1]).toString();
                    const contract = '0x' + log.topics[2].slice(-40);
                    const gasLimit = BigInt(log.topics[3]).toString();
                    
                    console.log(chalk.yellow(`\n  📤 Callback Details:`));
                    console.log(`     Target Chain: ${chainId}`);
                    console.log(`     Target Contract: ${contract}`);
                    console.log(`     Gas Limit: ${gasLimit}`);
                    
                    // Try to decode payload
                    const abiCoder = new ethers.AbiCoder();
                    const [payload] = abiCoder.decode(['bytes'], log.data);
                    const selector = payload.slice(0, 10);
                    
                    let funcName = 'Unknown';
                    if (selector === '0x8c90a800') funcName = 'executeLoopStep';
                    else if (selector === '0xaa0d9223') funcName = 'executeUnwindStep';
                    
                    console.log(`     Function: ${funcName} (${selector})`);
                } catch (e) {
                    console.log(chalk.red(`     Error decoding: ${e.message}`));
                }
            }
        }
        
    } catch (e) {
        console.log(chalk.red(`  Error: ${e.message}`));
    }
    
    console.log('');
}

async function showRecentTransactions() {
    console.log(chalk.yellow('📜 Recent Transactions'));
    console.log(chalk.gray('─'.repeat(50)));
    
    try {
        const head = await rnkClient.getHeadNumber(CONTRACTS.rvmId);
        const headNum = parseInt(head, 16);
        
        if (headNum === 0) {
            console.log(chalk.gray('  No transactions'));
            return;
        }
        
        const from = Math.max(1, headNum - 9);
        const fromHex = '0x' + from.toString(16);
        const limitHex = '0xa'; // 10 txs
        
        const txs = await rnkClient.getTransactions(CONTRACTS.rvmId, fromHex, limitHex);
        
        const table = new Table({
            head: ['#', 'Status', 'Type', 'Gas', 'Ref Chain', 'Time'],
            style: { head: ['yellow'] }
        });
        
        for (const tx of (txs || []).reverse()) {
            const txNum = parseInt(tx.number, 16);
            const status = tx.status === 1 ? chalk.green('✓') : chalk.red('✗');
            const type = tx.createContract ? 'Deploy' : 
                        (tx.data?.startsWith('0x0d152c2c') ? 'react()' : 'Other');
            const time = new Date(tx.time * 1000).toLocaleTimeString();
            
            table.push([txNum, status, type, tx.used, tx.refChainId, time]);
        }
        
        console.log(table.toString());
        console.log('');
        console.log(chalk.gray(`Tip: Use --tx <number> to debug a specific transaction`));
        console.log(chalk.gray(`Tip: Use --logs <number> to see logs for a transaction`));
        
    } catch (e) {
        console.log(chalk.red(`  Error: ${e.message}`));
    }
    
    console.log('');
}

// ═══════════════════════════════════════════════════════════════
//                         MAIN
// ═══════════════════════════════════════════════════════════════

async function main() {
    if (specificTx) {
        await debugTransaction(specificTx);
        return;
    }
    
    if (logsForTx) {
        await debugTransactionLogs(logsForTx);
        return;
    }
    
    // Full debug
    await debugRvmState();
    await showRecentTransactions();
}

main().catch(console.error);
