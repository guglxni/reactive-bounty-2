/**
 * RNK (Reactive Network) RPC Client
 * 
 * Provides methods for querying Reactive Network-specific RPC endpoints
 */

import { NETWORKS, RNK_METHODS } from './config.js';
import logger from './logger.js';

class RnkClient {
    constructor(rpcUrl = NETWORKS.lasna.rpc) {
        this.rpcUrl = rpcUrl;
        this.requestId = 1;
    }

    async call(method, params = []) {
        const body = {
            jsonrpc: '2.0',
            method,
            params,
            id: this.requestId++
        };

        try {
            const response = await fetch(this.rpcUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body)
            });

            const data = await response.json();
            
            if (data.error) {
                throw new Error(`RPC Error: ${data.error.message}`);
            }

            return data.result;
        } catch (error) {
            logger.error(`RNK RPC call failed: ${method}`, { error: error.message }, 'lasna');
            throw error;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                         VM METHODS
    // ═══════════════════════════════════════════════════════════════

    /**
     * Get VM status for a given RVM ID
     */
    async getVm(rvmId) {
        return this.call(RNK_METHODS.getVm, [rvmId]);
    }

    /**
     * Get the latest transaction number for an RVM
     */
    async getHeadNumber(rvmId) {
        return this.call(RNK_METHODS.getHeadNumber, [rvmId]);
    }

    /**
     * Get RVM ID for a reactive contract address
     */
    async getRnkAddressMapping(contractAddress) {
        return this.call(RNK_METHODS.getRnkAddressMapping, [contractAddress]);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     SUBSCRIPTION METHODS
    // ═══════════════════════════════════════════════════════════════

    /**
     * Get all subscriptions for an RVM
     */
    async getSubscribers(rvmId) {
        return this.call(RNK_METHODS.getSubscribers, [rvmId]);
    }

    /**
     * Get all active filters (subscriptions) on the network
     */
    async getFilters() {
        return this.call(RNK_METHODS.getFilters, []);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     TRANSACTION METHODS
    // ═══════════════════════════════════════════════════════════════

    /**
     * Get transactions for an RVM
     * @param rvmId - The RVM ID
     * @param from - Starting transaction number (hex)
     * @param limit - Max transactions to return (hex)
     */
    async getTransactions(rvmId, from = '0x1', limit = '0x100') {
        return this.call(RNK_METHODS.getTransactions, [rvmId, from, limit]);
    }

    /**
     * Get logs for a specific transaction
     */
    async getTransactionLogs(rvmId, txNumber) {
        return this.call(RNK_METHODS.getTransactionLogs, [rvmId, txNumber]);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     HELPER METHODS
    // ═══════════════════════════════════════════════════════════════

    /**
     * Check if a subscription exists for the given parameters
     */
    async checkSubscription(rvmId, chainId, contractAddress, topic0) {
        const subscribers = await this.getSubscribers(rvmId);
        
        if (!subscribers || subscribers.length === 0) {
            return { exists: false, subscription: null };
        }

        const matching = subscribers.find(sub => 
            sub.chainId === chainId &&
            sub.contract.toLowerCase() === contractAddress.toLowerCase() &&
            sub.topics[0]?.toLowerCase() === topic0.toLowerCase()
        );

        return {
            exists: !!matching,
            subscription: matching
        };
    }

    /**
     * Get recent RVM activity summary
     */
    async getActivitySummary(rvmId) {
        const [vm, headNumber, subscribers] = await Promise.all([
            this.getVm(rvmId).catch(() => null),
            this.getHeadNumber(rvmId).catch(() => '0x0'),
            this.getSubscribers(rvmId).catch(() => [])
        ]);

        const txCount = parseInt(headNumber, 16);
        
        return {
            rvmId,
            active: !!vm,
            lastTxNumber: txCount,
            contracts: vm?.contracts || 0,
            subscriptions: subscribers?.length || 0,
            lastActivity: vm?.lastTxNumber ? parseInt(vm.lastTxNumber, 16) : 0
        };
    }

    /**
     * Watch for new transactions on an RVM (polling)
     */
    async watchTransactions(rvmId, callback, pollInterval = 5000) {
        let lastTxNumber = 0;

        const poll = async () => {
            try {
                const headNumber = await this.getHeadNumber(rvmId);
                const currentTxNumber = parseInt(headNumber, 16);

                if (currentTxNumber > lastTxNumber) {
                    // Fetch new transactions
                    const fromHex = '0x' + (lastTxNumber + 1).toString(16);
                    const limitHex = '0x' + (currentTxNumber - lastTxNumber).toString(16);
                    
                    const txs = await this.getTransactions(rvmId, fromHex, limitHex);
                    
                    for (const tx of txs || []) {
                        await callback(tx);
                    }

                    lastTxNumber = currentTxNumber;
                }
            } catch (error) {
                logger.error(`Polling error: ${error.message}`, null, 'rvm');
            }
        };

        // Initial poll
        await poll();

        // Start polling interval
        const intervalId = setInterval(poll, pollInterval);

        // Return stop function
        return () => clearInterval(intervalId);
    }
}

export default RnkClient;
