#!/usr/bin/env node

/**
 * Live Address Verification Tool
 * Checks if an address has an active position and verifies all contract calls work
 */

import { ethers } from 'ethers';
import chalk from 'chalk';
import dotenv from 'dotenv';
import { NETWORKS, CONTRACTS } from './config.js';

dotenv.config();

const sepoliaProvider = new ethers.JsonRpcProvider(NETWORKS.sepolia.rpc);

const MANAGER_ABI = [
    'function getPosition(address user) view returns (tuple(address collateralAsset, address borrowAsset, uint256 initialCollateral, uint256 targetLeverage, uint256 currentLeverage, uint256 maxIterations, uint256 currentIteration, uint256 minHealthFactor, uint256 slippageTolerance, uint8 state, uint256 lastUpdateBlock, bool useFlashLoan, bool sameAssetLoop, uint256 maxGasSpend, uint256 gasSpentSoFar, uint256 twapBlockInterval, bytes32 executionSalt, uint256 takeProfitPrice, uint256 stopLossPrice))',
    'function getHealthFactor(address user) view returns (uint256)',
    'function getCurrentLeverage(address user) view returns (uint256)',
    'function hasPosition(address user) view returns (bool)',
];

const managerContract = new ethers.Contract(CONTRACTS.manager, MANAGER_ABI, sepoliaProvider);

async function verifyAddress(address) {
    console.log(chalk.bold.cyan('\n╔════════════════════════════════════════════════════════════════╗'));
    console.log(chalk.bold.cyan('║              LIVE ADDRESS VERIFICATION TOOL                     ║'));
    console.log(chalk.bold.cyan('╚════════════════════════════════════════════════════════════════╝\n'));

    console.log(chalk.white(`Address: ${chalk.yellow(address)}\n`));

    const results = {
        address: address,
        isValid: false,
        hasPosition: false,
        position: null,
        healthFactor: null,
        leverage: null,
        errors: []
    };

    try {
        // 1. Validate address format
        console.log(chalk.cyan('1. Validating address format...'));
        try {
            const checksummed = ethers.getAddress(address);
            console.log(chalk.green('   ✅ Valid Ethereum address\n'));
            results.isValid = true;
            results.address = checksummed;
        } catch (e) {
            console.log(chalk.red('   ❌ Invalid address format\n'));
            results.errors.push('Invalid address format');
            return results;
        }

        // 2. Check if address has position
        console.log(chalk.cyan('2. Checking position status...'));
        const hasPos = await managerContract.hasPosition(address);
        console.log(hasPos ? chalk.green('   ✅ Position exists') : chalk.yellow('   ⚠️  No active position\n'));
        results.hasPosition = hasPos;

        // 3. Get position details
        console.log(chalk.cyan('3. Fetching position details...'));
        try {
            const pos = await managerContract.getPosition(address);
            results.position = pos;
            
            console.log(chalk.white('   Position Data:'));
            console.log(chalk.white(`   ├─ State: ${pos.state.toString()} (${getStateName(pos.state)})`));
            console.log(chalk.white(`   ├─ Collateral Asset: ${pos.collateralAsset}`));
            console.log(chalk.white(`   ├─ Borrow Asset: ${pos.borrowAsset}`));
            console.log(chalk.white(`   ├─ Initial Collateral: ${ethers.formatEther(pos.initialCollateral)} ETH`));
            console.log(chalk.white(`   ├─ Target Leverage: ${formatLeverage(pos.targetLeverage)}x`));
            console.log(chalk.white(`   ├─ Current Leverage: ${formatLeverage(pos.currentLeverage)}x`));
            console.log(chalk.white(`   ├─ Iteration: ${pos.currentIteration.toString()}/${pos.maxIterations.toString()}`));
            console.log(chalk.white(`   ├─ Min Health Factor: ${formatHealthFactor(pos.minHealthFactor)}`));
            console.log(chalk.white(`   ├─ Use Flash Loan: ${pos.useFlashLoan ? '✅' : '❌'}`));
            console.log(chalk.white(`   ├─ Same Asset Loop: ${pos.sameAssetLoop ? '✅' : '❌'}`));
            console.log(chalk.white(`   └─ Last Update Block: ${pos.lastUpdateBlock.toString()}\n`));
            
            if (pos.state === 0n && pos.initialCollateral === 0n) {
                console.log(chalk.yellow('   ⚠️  Position structure exists but has no collateral (IDLE/CLOSED)\n'));
            } else {
                console.log(chalk.green('   ✅ Active position with collateral\n'));
            }
        } catch (e) {
            console.log(chalk.red(`   ❌ Error fetching position: ${e.message}\n`));
            results.errors.push(`Position fetch error: ${e.message}`);
        }

        // 4. Get health factor
        console.log(chalk.cyan('4. Checking health factor...'));
        try {
            const hf = await managerContract.getHealthFactor(address);
            results.healthFactor = hf;
            
            const hfValue = parseFloat(ethers.formatEther(hf));
            let hfStatus = '';
            
            if (hfValue === 0) {
                hfStatus = chalk.yellow('No active position');
            } else if (hfValue >= 2.0) {
                hfStatus = chalk.green('💚 Safe');
            } else if (hfValue >= 1.5) {
                hfStatus = chalk.yellow('💛 Caution');
            } else if (hfValue >= 1.2) {
                hfStatus = chalk.magenta('🧡 Warning');
            } else {
                hfStatus = chalk.red('❤️ DANGER');
            }
            
            console.log(chalk.white(`   Health Factor: ${hfValue.toFixed(4)} ${hfStatus}\n`));
        } catch (e) {
            console.log(chalk.red(`   ❌ Error fetching health factor: ${e.message}\n`));
            results.errors.push(`Health factor fetch error: ${e.message}`);
        }

        // 5. Get current leverage
        console.log(chalk.cyan('5. Getting current leverage...'));
        try {
            const lev = await managerContract.getCurrentLeverage(address);
            results.leverage = lev;
            
            const levValue = parseFloat(ethers.formatEther(lev));
            console.log(chalk.white(`   Current Leverage: ${levValue.toFixed(2)}x\n`));
        } catch (e) {
            console.log(chalk.red(`   ❌ Error fetching leverage: ${e.message}\n`));
            results.errors.push(`Leverage fetch error: ${e.message}`);
        }

        // Summary
        console.log(chalk.bold.cyan('═'.repeat(60)));
        console.log(chalk.bold.white('VERIFICATION SUMMARY'));
        console.log(chalk.bold.cyan('═'.repeat(60)));
        
        console.log(chalk.white(`Address Valid: ${results.isValid ? chalk.green('✅') : chalk.red('❌')}`));
        console.log(chalk.white(`Has Position: ${results.hasPosition ? chalk.green('✅') : chalk.yellow('⚠️')}`));
        console.log(chalk.white(`Contract Calls: ${results.errors.length === 0 ? chalk.green('✅ All working') : chalk.red(`❌ ${results.errors.length} errors`)}`));
        
        if (results.position && results.position.initialCollateral > 0n) {
            console.log(chalk.bold.green('\n✅ ADDRESS IS SUITABLE FOR TESTING!'));
            console.log(chalk.white('This address has an active position and all contract calls work.\n'));
        } else if (results.hasPosition) {
            console.log(chalk.bold.yellow('\n⚠️  ADDRESS HAS POSITION STRUCTURE BUT NO COLLATERAL'));
            console.log(chalk.white('This address previously had a position that was closed.\n'));
        } else {
            console.log(chalk.bold.yellow('\n⚠️  ADDRESS HAS NO ACTIVE POSITION'));
            console.log(chalk.white('Use an address that has deposited and created a leveraged position.\n'));
        }
        
        console.log(chalk.bold.cyan('═'.repeat(60) + '\n'));

    } catch (error) {
        console.error(chalk.red('❌ Verification failed:'), error.message);
        results.errors.push(error.message);
    }

    return results;
}

function getStateName(state) {
    const states = {
        0: 'IDLE',
        1: 'LOOPING',
        2: 'UNWINDING',
        3: 'EMERGENCY'
    };
    return states[Number(state)] || 'UNKNOWN';
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

// CLI Interface
const args = process.argv.slice(2);
const address = args[0] || '0x742d35Cc6634C0532925a3b844Bc9e7595f89999';

console.log(chalk.cyan('🔍 Starting verification...\n'));

verifyAddress(address)
    .then(results => {
        if (results.errors.length > 0) {
            process.exit(1);
        }
        process.exit(0);
    })
    .catch(error => {
        console.error(chalk.red('\n❌ Fatal error:'), error);
        process.exit(1);
    });
