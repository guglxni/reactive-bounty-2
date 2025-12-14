#!/usr/bin/env node

/**
 * Fund Callback Proxy Tool
 * 
 * Deposits ETH to callback proxy reserves for a specific RVM ID
 * This is CRITICAL for callbacks to be delivered to origin chains
 * 
 * Usage:
 *   node fund-reserves.js                    # Fund current RVM ID with 0.1 ETH
 *   node fund-reserves.js --amount 0.5       # Fund with specific amount
 *   node fund-reserves.js --check            # Only check balance
 *   node fund-reserves.js --address <addr>   # Fund different address
 */

import { ethers } from 'ethers';
import chalk from 'chalk';
import dotenv from 'dotenv';
import { NETWORKS, CONTRACTS, ABIS } from './config.js';
import logger from './logger.js';

dotenv.config();

// ═══════════════════════════════════════════════════════════════
//                         PARSE ARGS
// ═══════════════════════════════════════════════════════════════

const args = process.argv.slice(2);
const amountIdx = args.indexOf('--amount');
const addressIdx = args.indexOf('--address');
const checkOnly = args.includes('--check');

const fundAmount = amountIdx !== -1 ? args[amountIdx + 1] : '0.1';
const targetAddress = addressIdx !== -1 ? args[addressIdx + 1] : CONTRACTS.rvmId;

// ═══════════════════════════════════════════════════════════════
//                      CALLBACK PROXY ABI
// ═══════════════════════════════════════════════════════════════

const CALLBACK_PROXY_ABI = [
    'function depositTo(address _target) external payable',
    'function withdrawTo(address payable _target) external',
    'function reserves(address) external view returns (uint256)'
];

// ═══════════════════════════════════════════════════════════════
//                         MAIN FUNCTIONS
// ═══════════════════════════════════════════════════════════════

async function checkReserves(provider, proxyAddress, targetAddr) {
    const proxy = new ethers.Contract(proxyAddress, CALLBACK_PROXY_ABI, provider);
    const balance = await proxy.reserves(targetAddr);
    return balance;
}

async function main() {
    console.log('');
    console.log(chalk.bold.magenta('═══════════════════════════════════════════════════════════════'));
    console.log(chalk.bold.magenta('              CALLBACK PROXY RESERVES MANAGER'));
    console.log(chalk.bold.magenta('═══════════════════════════════════════════════════════════════'));
    console.log('');

    const sepoliaProvider = new ethers.JsonRpcProvider(NETWORKS.sepolia.rpc);
    
    console.log(chalk.yellow('📍 Configuration'));
    console.log(chalk.gray('─'.repeat(50)));
    console.log(`  Callback Proxy: ${chalk.white(CONTRACTS.callbackProxy)}`);
    console.log(`  Target Address: ${chalk.white(targetAddress)}`);
    console.log(`  Fund Amount:    ${chalk.white(fundAmount)} ETH`);
    console.log('');

    // Check current reserves
    console.log(chalk.yellow('💰 Current Reserves'));
    console.log(chalk.gray('─'.repeat(50)));
    
    const currentReserves = await checkReserves(sepoliaProvider, CONTRACTS.callbackProxy, targetAddress);
    const reservesEth = ethers.formatEther(currentReserves);
    
    console.log(`  Address: ${chalk.white(targetAddress)}`);
    console.log(`  Balance: ${parseFloat(reservesEth) > 0 ? chalk.green(reservesEth) : chalk.red(reservesEth)} ETH`);
    console.log('');

    if (parseFloat(reservesEth) === 0) {
        console.log(chalk.red.bold('  ⚠️  ZERO RESERVES - Callbacks will NOT be delivered!'));
        console.log('');
    }

    // Also check deployer reserves for comparison
    const deployerReserves = await checkReserves(sepoliaProvider, CONTRACTS.callbackProxy, CONTRACTS.deployerAddress);
    const deployerEth = ethers.formatEther(deployerReserves);
    
    console.log(chalk.gray(`  (Deployer reserves: ${deployerEth} ETH at ${CONTRACTS.deployerAddress})`));
    console.log('');

    if (checkOnly) {
        console.log(chalk.gray('Check only mode - not funding.'));
        return;
    }

    // Check for private key
    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) {
        console.log(chalk.red('❌ Error: PRIVATE_KEY not found in environment'));
        console.log('');
        console.log(chalk.yellow('To fund reserves, set your private key:'));
        console.log(chalk.gray('  export PRIVATE_KEY="your-private-key"'));
        console.log('');
        console.log(chalk.yellow('Or add to .env file:'));
        console.log(chalk.gray('  PRIVATE_KEY=your-private-key'));
        console.log('');
        console.log(chalk.yellow('Then run:'));
        console.log(chalk.gray(`  node fund-reserves.js --amount ${fundAmount}`));
        console.log('');
        
        // Show the cast command as alternative
        console.log(chalk.yellow('Alternatively, use cast:'));
        console.log(chalk.gray(`  cast send --rpc-url ${NETWORKS.sepolia.rpc} \\`));
        console.log(chalk.gray(`    --private-key $PRIVATE_KEY \\`));
        console.log(chalk.gray(`    ${CONTRACTS.callbackProxy} \\`));
        console.log(chalk.gray(`    --value ${fundAmount}ether \\`));
        console.log(chalk.gray(`    "depositTo(address)" ${targetAddress}`));
        return;
    }

    // Create wallet and fund
    const wallet = new ethers.Wallet(privateKey, sepoliaProvider);
    const walletBalance = await sepoliaProvider.getBalance(wallet.address);
    
    console.log(chalk.yellow('👛 Wallet Info'));
    console.log(chalk.gray('─'.repeat(50)));
    console.log(`  Address: ${chalk.white(wallet.address)}`);
    console.log(`  Balance: ${chalk.white(ethers.formatEther(walletBalance))} ETH`);
    console.log('');

    const fundAmountWei = ethers.parseEther(fundAmount);
    if (walletBalance < fundAmountWei) {
        console.log(chalk.red(`❌ Insufficient balance to fund ${fundAmount} ETH`));
        return;
    }

    // Confirm
    console.log(chalk.yellow.bold(`💳 Funding ${fundAmount} ETH to reserves...`));
    console.log('');

    const proxy = new ethers.Contract(CONTRACTS.callbackProxy, CALLBACK_PROXY_ABI, wallet);
    
    try {
        const tx = await proxy.depositTo(targetAddress, { value: fundAmountWei });
        console.log(`  TX Hash: ${chalk.cyan(tx.hash)}`);
        console.log(chalk.gray('  Waiting for confirmation...'));
        
        const receipt = await tx.wait();
        
        if (receipt.status === 1) {
            console.log(chalk.green.bold('  ✅ Transaction confirmed!'));
        } else {
            console.log(chalk.red.bold('  ❌ Transaction failed!'));
        }
        
        // Check new balance
        const newReserves = await checkReserves(sepoliaProvider, CONTRACTS.callbackProxy, targetAddress);
        console.log('');
        console.log(chalk.green(`  New reserves: ${ethers.formatEther(newReserves)} ETH`));
        
    } catch (e) {
        console.log(chalk.red(`  ❌ Error: ${e.message}`));
    }

    console.log('');
}

main().catch(console.error);
