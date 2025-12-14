#!/usr/bin/env node

/**
 * Status Checker for Reactive Auto-Looper
 * 
 * Displays current state of:
 * - Position on Sepolia
 * - RVM status on Lasna
 * - Subscription status
 * - Callback proxy reserves
 * 
 * Usage: node check-status.js [--user <address>]
 */

import { ethers } from 'ethers';
import chalk from 'chalk';
import boxen from 'boxen';
import Table from 'cli-table3';
import { NETWORKS, CONTRACTS, TOPICS, ABIS, POSITION_STATES } from './config.js';
import logger from './logger.js';
import RnkClient from './rnk-client.js';

// ═══════════════════════════════════════════════════════════════
//                         CONFIGURATION
// ═══════════════════════════════════════════════════════════════

// Parse command line args
const args = process.argv.slice(2);
const userIdx = args.indexOf('--user');
const userAddress = userIdx !== -1 && args[userIdx + 1] 
    ? args[userIdx + 1] 
    : CONTRACTS.deployerAddress;

// ═══════════════════════════════════════════════════════════════
//                         PROVIDERS
// ═══════════════════════════════════════════════════════════════

const sepoliaProvider = new ethers.JsonRpcProvider(NETWORKS.sepolia.rpc);
const rnkClient = new RnkClient();

// Contract instances
const managerContract = new ethers.Contract(
    CONTRACTS.manager,
    ABIS.manager,
    sepoliaProvider
);

const callbackProxyContract = new ethers.Contract(
    CONTRACTS.callbackProxy,
    ABIS.callbackProxy,
    sepoliaProvider
);

// ═══════════════════════════════════════════════════════════════
//                         STATUS CHECKS
// ═══════════════════════════════════════════════════════════════

async function checkPosition(user) {
    try {
        const position = await managerContract.getPosition(user);
        return {
            collateralAsset: position[0],
            borrowAsset: position[1],
            initialCollateral: position[2].toString(),
            targetLeverage: position[3].toString(),
            currentLeverage: position[4].toString(),
            iteration: position[5].toString(),
            state: Number(position[6])
        };
    } catch (e) {
        return null;
    }
}

async function checkHealthFactor(user) {
    try {
        const hf = await managerContract.getHealthFactor(user);
        return hf.toString();
    } catch (e) {
        return null;
    }
}

async function checkCallbackReserves(rvmId) {
    try {
        const reserves = await callbackProxyContract.reserves(rvmId);
        return reserves.toString();
    } catch (e) {
        return '0';
    }
}

async function checkRvmStatus() {
    try {
        const vm = await rnkClient.getVm(CONTRACTS.rvmId);
        return {
            active: true,
            lastTxNumber: parseInt(vm.lastTxNumber, 16),
            contracts: vm.contracts
        };
    } catch (e) {
        return { active: false, lastTxNumber: 0, contracts: 0 };
    }
}

async function checkSubscription() {
    try {
        const result = await rnkClient.checkSubscription(
            CONTRACTS.rvmId,
            NETWORKS.sepolia.chainId,
            CONTRACTS.manager,
            TOPICS.PositionUpdated
        );
        return result;
    } catch (e) {
        return { exists: false, subscription: null };
    }
}

async function getRecentRvmTransactions(limit = 5) {
    try {
        const headNumber = await rnkClient.getHeadNumber(CONTRACTS.rvmId);
        const head = parseInt(headNumber, 16);
        
        if (head === 0) return [];
        
        const from = Math.max(1, head - limit + 1);
        const fromHex = '0x' + from.toString(16);
        const limitHex = '0x' + limit.toString(16);
        
        const txs = await rnkClient.getTransactions(CONTRACTS.rvmId, fromHex, limitHex);
        return txs || [];
    } catch (e) {
        return [];
    }
}

// ═══════════════════════════════════════════════════════════════
//                         DISPLAY HELPERS
// ═══════════════════════════════════════════════════════════════

function statusIcon(ok) {
    return ok ? chalk.green('✓') : chalk.red('✗');
}

function formatWei(wei) {
    const eth = Number(wei) / 1e18;
    if (eth === 0) return chalk.red('0 ETH');
    if (eth < 0.01) return chalk.yellow(`${eth.toFixed(6)} ETH`);
    return chalk.green(`${eth.toFixed(4)} ETH`);
}

// ═══════════════════════════════════════════════════════════════
//                         MAIN STATUS CHECK
// ═══════════════════════════════════════════════════════════════

async function checkStatus() {
    console.log('');
    console.log(chalk.bold.blue('═══════════════════════════════════════════════════════════════'));
    console.log(chalk.bold.blue('           REACTIVE AUTO-LOOPER STATUS CHECK'));
    console.log(chalk.bold.blue('═══════════════════════════════════════════════════════════════'));
    console.log('');

    // ─────────────────────────────────────────────────────────────
    // SEPOLIA POSITION STATUS
    // ─────────────────────────────────────────────────────────────
    
    console.log(chalk.cyan.bold('📊 SEPOLIA - Position Status'));
    console.log(chalk.gray('─'.repeat(50)));
    
    const position = await checkPosition(userAddress);
    const healthFactor = await checkHealthFactor(userAddress);
    
    if (position) {
        const stateInfo = POSITION_STATES[position.state] || { name: 'UNKNOWN', emoji: '❓', color: 'white' };
        
        const positionTable = new Table({
            style: { head: ['cyan'] }
        });
        
        positionTable.push(
            ['User', userAddress],
            ['State', `${stateInfo.emoji} ${chalk[stateInfo.color](stateInfo.name)}`],
            ['Current Leverage', logger.formatLeverage(position.currentLeverage)],
            ['Target Leverage', logger.formatLeverage(position.targetLeverage)],
            ['Health Factor', healthFactor ? (Number(healthFactor) / 1e18).toFixed(4) : 'N/A'],
            ['Iteration', position.iteration],
            ['Initial Collateral', formatWei(position.initialCollateral)]
        );
        
        console.log(positionTable.toString());
    } else {
        console.log(chalk.gray('  No position found for this user'));
    }
    
    console.log('');

    // ─────────────────────────────────────────────────────────────
    // RVM STATUS
    // ─────────────────────────────────────────────────────────────
    
    console.log(chalk.magenta.bold('⚡ LASNA RVM - Reactive Contract Status'));
    console.log(chalk.gray('─'.repeat(50)));
    
    const rvmStatus = await checkRvmStatus();
    
    const rvmTable = new Table({
        style: { head: ['magenta'] }
    });
    
    rvmTable.push(
        ['RVM ID', CONTRACTS.rvmId],
        ['Reactive Contract', CONTRACTS.reactiveContract],
        ['Status', statusIcon(rvmStatus.active) + ' ' + (rvmStatus.active ? 'Active' : 'Inactive')],
        ['Total Transactions', rvmStatus.lastTxNumber.toString()],
        ['Deployed Contracts', rvmStatus.contracts.toString()]
    );
    
    console.log(rvmTable.toString());
    console.log('');

    // ─────────────────────────────────────────────────────────────
    // SUBSCRIPTION STATUS
    // ─────────────────────────────────────────────────────────────
    
    console.log(chalk.yellow.bold('🔔 SUBSCRIPTION STATUS'));
    console.log(chalk.gray('─'.repeat(50)));
    
    const subscription = await checkSubscription();
    
    const subTable = new Table({
        style: { head: ['yellow'] }
    });
    
    if (subscription.exists) {
        subTable.push(
            ['Subscription', statusIcon(true) + ' Active'],
            ['Chain ID', subscription.subscription.chainId.toString()],
            ['Contract', subscription.subscription.contract],
            ['Topic 0', logger.truncateAddress(subscription.subscription.topics[0], 10)]
        );
    } else {
        subTable.push(
            ['Subscription', statusIcon(false) + ' NOT FOUND'],
            ['Expected Chain', NETWORKS.sepolia.chainId.toString()],
            ['Expected Contract', CONTRACTS.manager],
            ['Expected Topic', logger.truncateAddress(TOPICS.PositionUpdated, 10)]
        );
    }
    
    console.log(subTable.toString());
    console.log('');

    // ─────────────────────────────────────────────────────────────
    // CALLBACK PROXY RESERVES
    // ─────────────────────────────────────────────────────────────
    
    console.log(chalk.green.bold('💰 CALLBACK PROXY RESERVES'));
    console.log(chalk.gray('─'.repeat(50)));
    
    const reserves = await checkCallbackReserves(CONTRACTS.rvmId);
    const hasReserves = BigInt(reserves) > 0n;
    
    const reservesTable = new Table({
        style: { head: ['green'] }
    });
    
    reservesTable.push(
        ['Callback Proxy', CONTRACTS.callbackProxy],
        ['RVM ID', CONTRACTS.rvmId],
        ['Reserves', formatWei(reserves)],
        ['Status', statusIcon(hasReserves) + ' ' + (hasReserves ? 'Funded' : 'EMPTY - CALLBACKS WILL FAIL!')]
    );
    
    console.log(reservesTable.toString());
    
    if (!hasReserves) {
        console.log('');
        console.log(boxen(
            chalk.red.bold('⚠️  CRITICAL: Callback proxy has no reserves!\n\n') +
            chalk.white('Callbacks from RVM will NOT be delivered to Sepolia.\n') +
            chalk.white('Run the following to fund:\n\n') +
            chalk.yellow(`cast send ${CONTRACTS.callbackProxy} "depositTo(address)" ${CONTRACTS.rvmId} \\\n`) +
            chalk.yellow(`    --value 0.1ether --private-key $SEPOLIA_PRIVATE_KEY \\\n`) +
            chalk.yellow(`    --rpc-url ${NETWORKS.sepolia.rpc}`),
            { padding: 1, borderColor: 'red', borderStyle: 'double' }
        ));
    }
    
    console.log('');

    // ─────────────────────────────────────────────────────────────
    // RECENT RVM TRANSACTIONS
    // ─────────────────────────────────────────────────────────────
    
    console.log(chalk.blue.bold('📜 RECENT RVM TRANSACTIONS'));
    console.log(chalk.gray('─'.repeat(50)));
    
    const recentTxs = await getRecentRvmTransactions(5);
    
    if (recentTxs.length > 0) {
        const txTable = new Table({
            head: ['#', 'Status', 'Type', 'Gas', 'Ref Chain', 'Time'],
            style: { head: ['blue'] }
        });
        
        for (const tx of recentTxs.reverse()) {
            const txNum = parseInt(tx.number, 16);
            const status = tx.status === 1 ? chalk.green('✓') : chalk.red('✗');
            const type = tx.createContract ? 'Deploy' : 
                        (tx.data?.startsWith('0x0d152c2c') ? 'react()' : 'Other');
            const time = new Date(tx.time * 1000).toLocaleTimeString();
            
            txTable.push([
                txNum,
                status,
                type,
                tx.used,
                tx.refChainId,
                time
            ]);
        }
        
        console.log(txTable.toString());
    } else {
        console.log(chalk.gray('  No transactions found'));
    }
    
    console.log('');
    console.log(chalk.gray('─'.repeat(50)));
    console.log(chalk.gray(`Last checked: ${new Date().toISOString()}`));
    console.log('');
}

// Run
checkStatus().catch(console.error);
