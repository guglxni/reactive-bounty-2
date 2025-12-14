#!/usr/bin/env node

/**
 * Full E2E Test for Reactive Auto-Looper
 * 
 * This script:
 * 1. Checks all component states
 * 2. Opens a new position on Sepolia
 * 3. Monitors for RVM reaction on Lasna
 * 4. Monitors for callback execution on Sepolia
 * 5. Reports success/failure
 * 6. Sends Telegram notifications for all events
 * 
 * Usage:
 *   node e2e-test.js              # Full E2E flow
 *   node e2e-test.js --dry-run    # Check state only, don't create position
 *   node e2e-test.js --no-telegram # Skip Telegram notifications
 */

import { ethers } from 'ethers';
import chalk from 'chalk';
import dotenv from 'dotenv';
import { NETWORKS, CONTRACTS, TOPICS, ABIS, POSITION_STATES } from './config.js';
import logger from './logger.js';
import RnkClient from './rnk-client.js';
import { sendTelegramMessage, Notifications } from './telegram-bot.js';

dotenv.config();

const rnkClient = new RnkClient();
const isDryRun = process.argv.includes('--dry-run');
const noTelegram = process.argv.includes('--no-telegram');

// Telegram notification helper
async function notify(message) {
    if (!noTelegram) {
        await sendTelegramMessage(message);
    }
}

// ═══════════════════════════════════════════════════════════════
//                      PROVIDERS & CONTRACTS
// ═══════════════════════════════════════════════════════════════

const sepoliaProvider = new ethers.JsonRpcProvider(NETWORKS.sepolia.rpc);
const lasnaProvider = new ethers.JsonRpcProvider(NETWORKS.lasna.rpc);

// ═══════════════════════════════════════════════════════════════
//                     PREREQUISITE CHECKS
// ═══════════════════════════════════════════════════════════════

async function checkPrerequisites() {
    logger.header('PREREQUISITE CHECKS');
    let allGood = true;

    // 1. Check Manager contract
    logger.subheader('AutoLooperManager (Sepolia)');
    try {
        const code = await sepoliaProvider.getCode(CONTRACTS.manager);
        if (code === '0x') {
            logger.error('Manager contract not deployed');
            allGood = false;
        } else {
            logger.success(`Manager deployed at ${CONTRACTS.manager}`);
            
            // Check reactive contract setting
            const managerAbi = [
                'function reactiveContract() view returns (address)'
            ];
            const manager = new ethers.Contract(CONTRACTS.manager, managerAbi, sepoliaProvider);
            
            const reactiveAddr = await manager.reactiveContract();
            
            logger.info(`  Reactive Contract: ${reactiveAddr}`);
            
            if (reactiveAddr.toLowerCase() !== CONTRACTS.reactiveContract.toLowerCase()) {
                logger.warning(`  ⚠️ Reactive contract mismatch!`);
                logger.warning(`     Expected: ${CONTRACTS.reactiveContract}`);
            }
        }
    } catch (e) {
        logger.error(`Error checking Manager: ${e.message}`);
        allGood = false;
    }
    console.log('');

    // 2. Check Reactive contract
    logger.subheader('AutoLooperReactive (Lasna)');
    try {
        const code = await lasnaProvider.getCode(CONTRACTS.reactiveContract);
        if (code === '0x') {
            logger.error('Reactive contract not deployed');
            allGood = false;
        } else {
            logger.success(`Reactive contract deployed at ${CONTRACTS.reactiveContract}`);
        }
    } catch (e) {
        logger.error(`Error checking Reactive: ${e.message}`);
        allGood = false;
    }
    console.log('');

    // 3. Check RVM subscription
    logger.subheader('RVM Subscription');
    try {
        const subs = await rnkClient.getSubscribers(CONTRACTS.rvmId);
        const hasSub = subs?.some(s => 
            s.contract.toLowerCase() === CONTRACTS.manager.toLowerCase() &&
            s.topics[0]?.toLowerCase() === TOPICS.PositionUpdated.toLowerCase()
        );
        
        if (hasSub) {
            logger.success('Subscription active for PositionUpdated events');
        } else {
            logger.error('No subscription found for PositionUpdated events!');
            allGood = false;
        }
    } catch (e) {
        logger.error(`Error checking subscription: ${e.message}`);
        allGood = false;
    }
    console.log('');

    // 4. Check callback proxy reserves
    logger.subheader('Callback Proxy Reserves');
    try {
        const proxyAbi = ['function reserves(address) view returns (uint256)'];
        const proxy = new ethers.Contract(CONTRACTS.callbackProxy, proxyAbi, sepoliaProvider);
        const reserves = await proxy.reserves(CONTRACTS.rvmId);
        const reservesEth = ethers.formatEther(reserves);
        
        if (reserves > 0n) {
            logger.success(`Reserves: ${reservesEth} ETH for RVM ID ${logger.truncateAddress(CONTRACTS.rvmId)}`);
        } else {
            logger.error(`ZERO reserves for RVM ID ${CONTRACTS.rvmId}!`);
            logger.error('Callbacks cannot be delivered without reserves!');
            logger.warning('Run: node fund-reserves.js to fund');
            allGood = false;
        }
    } catch (e) {
        logger.error(`Error checking reserves: ${e.message}`);
        allGood = false;
    }
    console.log('');

    return allGood;
}

// ═══════════════════════════════════════════════════════════════
//                     OPEN POSITION
// ═══════════════════════════════════════════════════════════════

async function openPosition(wallet) {
    logger.header('OPENING NEW POSITION');
    
    const managerExtended = new ethers.Contract(CONTRACTS.manager, [
        ...ABIS.manager,
        'function closePosition()',
        'function requestUnwind()'
    ], wallet);
    const manager = managerExtended;
    
    // Check if user already has a position
    const hasPos = await manager.hasPosition(wallet.address);
    if (hasPos) {
        const pos = await manager.getPosition(wallet.address);
        const stateNum = Number(pos.state);
        const stateName = POSITION_STATES[stateNum]?.name || String(stateNum);
        const currentLeverage = Number(pos.currentLeverage);
        const hasDebt = currentLeverage > 1e18; // > 1x leverage means debt
        
        logger.warning(`User already has a position in state: ${stateName}`);
        logger.info(`Current leverage: ${(currentLeverage / 1e18).toFixed(4)}x, Has debt: ${hasDebt}`);
        
        // If position is IDLE (completed), we can close or it may need unwind if debt exists
        if (stateNum === 0) { // IDLE state
            if (hasDebt) {
                logger.info('Position is IDLE with debt - requesting unwind first...');
                try {
                    const unwindTx = await manager.requestUnwind();
                    logger.pending(`Unwind TX sent: ${unwindTx.hash}`);
                    await unwindTx.wait();
                    logger.success('Unwind requested! Position is now UNWINDING.');
                    logger.info('Please wait for RVM to process unwind callbacks, then run E2E again.');
                    return { success: false, reason: 'Unwind in progress - retry after completion' };
                } catch (e) {
                    logger.error(`Failed to request unwind: ${e.message}`);
                    return { success: false, reason: 'Failed to unwind existing position' };
                }
            } else {
                logger.info('Position is IDLE with no debt - closing to allow new position...');
                try {
                    const closeTx = await manager.closePosition();
                    logger.pending(`Close TX sent: ${closeTx.hash}`);
                    await closeTx.wait();
                    logger.success('Position closed successfully!');
                } catch (e) {
                    logger.error(`Failed to close position: ${e.message}`);
                    return { success: false, reason: 'Failed to close existing position' };
                }
            }
        } else if (stateNum === 2) { // UNWINDING state
            logger.info('Position is already UNWINDING - wait for completion');
            return { success: false, reason: 'Position is unwinding - wait for completion' };
        } else {
            logger.info('Position is active, cannot open new one');
            return { success: false, reason: `Position exists in ${stateName} state` };
        }
    }
    
    // Get loop fee
    const loopFee = await manager.loopFee();
    logger.info(`Loop fee: ${ethers.formatEther(loopFee)} ETH`);
    console.log('');

    // Define position parameters - Same-asset loop (WETH → WETH)
    // This bypasses DEX liquidity issues on testnet
    const WETH = '0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c';
    const depositAmount = ethers.parseEther('0.001'); // 0.001 WETH
    const targetLeverage = ethers.parseEther('2'); // 2x leverage
    const maxIterations = 5;

    logger.info('Opening position with parameters:');
    logger.info(`  Asset:            WETH (same-asset loop)`);
    logger.info(`  Deposit Amount:   ${ethers.formatEther(depositAmount)} WETH`);
    logger.info(`  Target Leverage:  ${ethers.formatEther(targetLeverage)}x`);
    logger.info(`  Max Iterations:   ${maxIterations}`);
    logger.info(`  Fee:              ${ethers.formatEther(loopFee)} ETH`);
    console.log('');

    try {
        // First, wrap ETH to WETH
        const wethContract = new ethers.Contract(WETH, [
            'function deposit() payable',
            'function approve(address spender, uint256 amount) returns (bool)',
            'function balanceOf(address) view returns (uint256)'
        ], wallet);
        
        // Check WETH balance
        const wethBalance = await wethContract.balanceOf(wallet.address);
        logger.info(`Current WETH balance: ${ethers.formatEther(wethBalance)}`);
        
        if (wethBalance < depositAmount) {
            logger.info('Wrapping ETH to WETH...');
            const wrapTx = await wethContract.deposit({ value: depositAmount });
            await wrapTx.wait();
            logger.success('ETH wrapped to WETH');
        }
        
        // Approve manager to spend WETH
        logger.info('Approving WETH for manager...');
        const approveTx = await wethContract.approve(CONTRACTS.manager, depositAmount);
        await approveTx.wait();
        logger.success('WETH approved');
        
        // Call depositSameAsset (no DEX swap needed)
        logger.info('Opening same-asset loop position...');
        const tx = await manager.depositSameAsset(
            WETH,
            depositAmount,
            targetLeverage,
            maxIterations,
            { value: loopFee }
        );
        
        logger.pending(`TX sent: ${tx.hash}`);
        logger.info('Waiting for confirmation...');
        
        const receipt = await tx.wait();
        
        if (receipt.status === 1) {
            logger.success('Position opened successfully!');
            
            // Find PositionCreated event
            const posCreatedLog = receipt.logs.find(
                l => l.topics[0]?.toLowerCase() === ethers.id('PositionCreated(address,address,address,uint256)').toLowerCase()
            );
            
            if (posCreatedLog) {
                const user = '0x' + posCreatedLog.topics[1].slice(-40);
                logger.success(`PositionCreated event emitted for user ${logger.truncateAddress(user)}`);
            }
            
            // Find PositionUpdated event
            const posUpdatedLog = receipt.logs.find(
                l => l.topics[0] === TOPICS.PositionUpdated
            );
            
            if (posUpdatedLog) {
                logger.success('PositionUpdated event emitted - RSC should react!');
            }
            
            return { success: true, receipt, txHash: tx.hash };
        } else {
            logger.error('Transaction failed!');
            return { success: false };
        }
    } catch (e) {
        logger.error(`Error opening position: ${e.message}`);
        if (e.message.includes('Position exists')) {
            logger.info('Tip: The user already has an active position');
        }
        return { success: false, error: e };
    }
}

// ═══════════════════════════════════════════════════════════════
//                     MONITOR RVM
// ═══════════════════════════════════════════════════════════════

async function waitForRvmReaction(startTxNum, timeout = 120000) {
    logger.header('WAITING FOR RVM REACTION');
    
    const startTime = Date.now();
    let lastTxNum = startTxNum;
    
    while (Date.now() - startTime < timeout) {
        const currentHead = await rnkClient.getHeadNumber(CONTRACTS.rvmId);
        const currentTxNum = parseInt(currentHead, 16);
        
        if (currentTxNum > lastTxNum) {
            logger.success(`New RVM transaction detected! TX #${currentTxNum}`);
            
            // Get transaction details
            const txHex = '0x' + currentTxNum.toString(16);
            const txs = await rnkClient.getTransactions(CONTRACTS.rvmId, txHex, '0x1');
            
            if (txs && txs.length > 0) {
                const tx = txs[0];
                if (tx.status === 1) {
                    logger.success('RVM transaction succeeded!');
                    
                    // Check for Callback event
                    const logs = await rnkClient.getTransactionLogs(CONTRACTS.rvmId, txHex);
                    const callbackLog = logs?.find(l => l.topics[0] === TOPICS.Callback);
                    
                    if (callbackLog) {
                        logger.success('Callback event emitted!');
                        return { success: true, txNum: currentTxNum, hasCallback: true };
                    } else {
                        logger.warning('No Callback event found in logs');
                        return { success: true, txNum: currentTxNum, hasCallback: false };
                    }
                } else {
                    logger.error('RVM transaction failed!');
                    return { success: false, txNum: currentTxNum };
                }
            }
            
            lastTxNum = currentTxNum;
        }
        
        process.stdout.write(chalk.gray(`\r  Waiting... (${Math.round((Date.now() - startTime) / 1000)}s)`));
        await new Promise(r => setTimeout(r, 3000));
    }
    
    console.log('');
    logger.error(`Timeout waiting for RVM reaction`);
    return { success: false, timeout: true };
}

// ═══════════════════════════════════════════════════════════════
//                   MONITOR CALLBACK DELIVERY
// ═══════════════════════════════════════════════════════════════

async function waitForCallbackDelivery(userAddr, timeout = 180000) {
    logger.header('WAITING FOR CALLBACK DELIVERY');
    
    const manager = new ethers.Contract(CONTRACTS.manager, ABIS.manager, sepoliaProvider);
    const startTime = Date.now();
    
    // Get initial position state
    const initialPos = await manager.getPosition(userAddr);
    const initialIteration = Number(initialPos.currentIteration);
    const initialLeverage = initialPos.currentLeverage;
    
    logger.info(`Initial state: ${POSITION_STATES[initialPos.state]?.name || initialPos.state}`);
    logger.info(`Initial iteration: ${initialIteration} / ${initialPos.maxIterations}`);
    logger.info(`Initial leverage: ${ethers.formatEther(initialLeverage)}x`);
    console.log('');
    
    while (Date.now() - startTime < timeout) {
        try {
            const pos = await manager.getPosition(userAddr);
            const currentIteration = Number(pos.currentIteration);
            
            // Check if iteration advanced OR leverage changed significantly
            if (currentIteration > initialIteration) {
                logger.success(`Callback delivered! Iteration advanced: ${initialIteration} -> ${currentIteration}`);
                logger.success(`New leverage: ${ethers.formatEther(pos.currentLeverage)}x`);
                return { success: true, newIteration: currentIteration, leverage: pos.currentLeverage };
            }
            
            // Check if leverage changed (callback executed loop step)
            const leverageChange = pos.currentLeverage - initialLeverage;
            if (leverageChange > ethers.parseEther('0.01')) { // > 0.01x change
                logger.success(`Callback delivered! Leverage changed: ${ethers.formatEther(initialLeverage)}x -> ${ethers.formatEther(pos.currentLeverage)}x`);
                return { success: true, newIteration: currentIteration, leverage: pos.currentLeverage };
            }
            
            // Check if state changed
            if (pos.state !== initialPos.state) {
                logger.success(`Position state changed: ${POSITION_STATES[initialPos.state]?.name} -> ${POSITION_STATES[pos.state]?.name}`);
                return { success: true, newIteration: currentIteration, leverage: pos.currentLeverage };
            }
        } catch (e) {
            logger.warning(`Error checking position: ${e.message}`);
        }
        
        process.stdout.write(chalk.gray(`\r  Waiting for callback... (${Math.round((Date.now() - startTime) / 1000)}s)`));
        await new Promise(r => setTimeout(r, 5000));
    }
    
    console.log('');
    logger.error(`Timeout waiting for callback delivery`);
    logger.warning('Callback may have been emitted but not delivered.');
    logger.warning('Check callback proxy reserves!');
    return { success: false, timeout: true };
}

// ═══════════════════════════════════════════════════════════════
//                         MAIN
// ═══════════════════════════════════════════════════════════════

async function main() {
    console.log('');
    console.log(chalk.bold.magenta('╔════════════════════════════════════════════════════════════════╗'));
    console.log(chalk.bold.magenta('║         REACTIVE AUTO-LOOPER E2E TEST                          ║'));
    console.log(chalk.bold.magenta('╚════════════════════════════════════════════════════════════════╝'));
    console.log('');

    // Send E2E test started notification
    await notify(Notifications.e2eTestStarted());

    const testDetails = [];

    // Step 1: Check prerequisites
    const prereqsOk = await checkPrerequisites();
    
    if (!prereqsOk) {
        console.log('');
        logger.error('Prerequisites check failed. Please fix issues above.');
        await notify(Notifications.e2eTestResult(false, ['Prerequisites check failed']));
        process.exit(1);
    }

    logger.success('All prerequisites passed!');
    testDetails.push('Prerequisites verified');
    console.log('');

    if (isDryRun) {
        logger.info('Dry run mode - not creating position');
        await notify(Notifications.e2eTestResult(true, ['Dry run: Prerequisites OK']));
        return;
    }

    // Check for private key
    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) {
        logger.error('PRIVATE_KEY not found in environment');
        logger.info('Set it via: export PRIVATE_KEY="your-key"');
        await notify(Notifications.e2eTestResult(false, ['PRIVATE_KEY not set']));
        process.exit(1);
    }

    const wallet = new ethers.Wallet(privateKey, sepoliaProvider);
    logger.info(`Using wallet: ${wallet.address}`);
    console.log('');

    // Get initial RVM state
    const initialHead = await rnkClient.getHeadNumber(CONTRACTS.rvmId);
    const initialTxNum = parseInt(initialHead, 16);
    logger.info(`Initial RVM TX count: ${initialTxNum}`);
    console.log('');

    // Step 2: Open position
    const openResult = await openPosition(wallet);
    if (!openResult.success) {
        logger.error('Failed to open position');
        await notify(Notifications.e2eTestResult(false, [`Failed to open position: ${openResult.reason || 'Unknown error'}`]));
        process.exit(1);
    }
    testDetails.push(`Position opened (TX: ${openResult.txHash?.slice(0, 10)}...)`);
    console.log('');

    // Step 3: Wait for RVM reaction
    await notify(`⏳ <b>Waiting for RVM reaction...</b>\n\nPosition opened, monitoring Lasna RVM for react() trigger.`);
    
    const rvmResult = await waitForRvmReaction(initialTxNum);
    if (!rvmResult.success) {
        logger.error('RVM reaction failed or timed out');
        await notify(Notifications.e2eTestResult(false, [...testDetails, 'RVM reaction failed/timeout']));
        process.exit(1);
    }
    testDetails.push(`RVM reaction detected (TX #${rvmResult.txNum})`);
    await notify(Notifications.rvmReaction(rvmResult.txNum, rvmResult.hasCallback));
    console.log('');

    if (!rvmResult.hasCallback) {
        logger.warning('RVM processed event but no callback emitted');
        logger.info('This might be expected if nextExecutionTime is in the future');
        await notify(Notifications.e2eTestResult(true, [...testDetails, 'RVM processed (no callback needed yet)']));
        process.exit(0);
    }

    // Step 4: Wait for callback delivery
    await notify(`⏳ <b>Waiting for callback delivery...</b>\n\nCallback emitted from RSC, waiting for execution on Sepolia.`);
    
    const cbResult = await waitForCallbackDelivery(wallet.address);
    
    console.log('');
    if (cbResult.success) {
        testDetails.push(`Callback delivered (Iteration: ${cbResult.newIteration})`);
        await notify(Notifications.callbackDelivered(wallet.address, cbResult.newIteration, ethers.formatEther(cbResult.leverage)));
        
        console.log(chalk.bold.green('═══════════════════════════════════════════════════════════════'));
        console.log(chalk.bold.green('                    ✅ E2E TEST PASSED!'));
        console.log(chalk.bold.green('═══════════════════════════════════════════════════════════════'));
        
        await notify(Notifications.e2eTestResult(true, testDetails));
    } else {
        console.log(chalk.bold.red('═══════════════════════════════════════════════════════════════'));
        console.log(chalk.bold.red('                    ❌ E2E TEST FAILED'));
        console.log(chalk.bold.red('═══════════════════════════════════════════════════════════════'));
        logger.info('Debug tips:');
        logger.info('  1. Run: node debug-rvm.js --logs <tx_number>');
        logger.info('  2. Check reserves: node fund-reserves.js --check');
        logger.info('  3. View live events: node watch-events.js');
        
        await notify(Notifications.e2eTestResult(false, [...testDetails, 'Callback delivery failed/timeout']));
    }
    console.log('');
}
main().catch(console.error);
