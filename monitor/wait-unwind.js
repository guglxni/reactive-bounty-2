/**
 * Wait for position unwind to complete
 * Monitors position state and leverage until fully unwound
 */

import { ethers } from 'ethers';
import config from './config.js';

const { CONTRACTS, NETWORKS, ABIS, POSITION_STATES } = config;

async function waitForUnwind() {
    // Load private key
    const PRIVATE_KEY = process.env.PRIVATE_KEY;
    if (!PRIVATE_KEY) {
        console.error('❌ PRIVATE_KEY not set');
        process.exit(1);
    }
    
    const provider = new ethers.JsonRpcProvider(NETWORKS.sepolia.rpc);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    
    const manager = new ethers.Contract(CONTRACTS.manager, [
        ...ABIS.manager,
        'function closePosition()',
        'function requestUnwind()'
    ], wallet);
    
    console.log('╔═══════════════════════════════════════════════╗');
    console.log('║      WAITING FOR POSITION UNWIND              ║');
    console.log('╚═══════════════════════════════════════════════╝');
    console.log('');
    console.log(`Wallet: ${wallet.address}`);
    console.log('');
    
    let attempts = 0;
    const maxAttempts = 60; // 5 minutes max
    const pollInterval = 5000; // 5 seconds
    
    while (attempts < maxAttempts) {
        attempts++;
        
        const hasPos = await manager.hasPosition(wallet.address);
        if (!hasPos) {
            console.log('✅ Position closed! Ready for new E2E test.');
            return;
        }
        
        const pos = await manager.getPosition(wallet.address);
        const stateNum = Number(pos.state);
        const stateName = POSITION_STATES[stateNum]?.name || String(stateNum);
        const leverage = (Number(pos.currentLeverage) / 1e18).toFixed(4);
        const hasDebt = Number(pos.currentLeverage) > 1e18;
        
        console.log(`[${new Date().toISOString()}] State: ${stateName}, Leverage: ${leverage}x, Debt: ${hasDebt}`);
        
        // If position is IDLE
        if (stateNum === 0) {
            if (hasDebt) {
                // Still has debt but IDLE - need to request unwind
                console.log('\\n⚠️ Position is IDLE but has debt - requesting unwind...');
                try {
                    const tx = await manager.requestUnwind();
                    console.log(`⏳ Unwind TX sent: ${tx.hash}`);
                    await tx.wait();
                    console.log('✅ Unwind requested!');
                } catch (e) {
                    console.error(`❌ Failed to request unwind: ${e.message}`);
                }
            } else {
                // No debt, can close
                console.log('\\n✅ Position is IDLE with no debt - closing...');
                try {
                    const tx = await manager.closePosition();
                    console.log(`⏳ Close TX sent: ${tx.hash}`);
                    await tx.wait();
                    console.log('✅ Position closed! Ready for new E2E test.');
                    return;
                } catch (e) {
                    console.error(`❌ Failed to close: ${e.message}`);
                }
            }
        } else if (stateNum === 2) {
            // UNWINDING - check if leverage is at 1x (fully unwound)
            if (!hasDebt) {
                console.log('\\n✅ Position fully unwound to 1x! Closing...');
                try {
                    const tx = await manager.closePosition();
                    console.log(`⏳ Close TX sent: ${tx.hash}`);
                    await tx.wait();
                    console.log('✅ Position closed! Ready for new E2E test.');
                    return;
                } catch (e) {
                    console.error(`❌ Failed to close: ${e.message}`);
                }
            } else {
                console.log('   ... waiting for RVM to process unwind callbacks');
            }
        }
        
        await new Promise(r => setTimeout(r, pollInterval));
    }
    
    console.log('\\n⚠️ Timeout waiting for unwind completion');
    console.log('Position may still be unwinding. Run again later.');
}

waitForUnwind().catch(console.error);
