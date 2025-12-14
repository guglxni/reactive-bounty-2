/**
 * Configuration for Reactive Auto-Looper Monitor
 * 
 * Contains all contract addresses, ABIs, and RPC endpoints
 */

import dotenv from 'dotenv';
dotenv.config({ path: '../.env' });

// ═══════════════════════════════════════════════════════════════
//                         NETWORK CONFIG
// ═══════════════════════════════════════════════════════════════

export const NETWORKS = {
    sepolia: {
        name: 'Sepolia',
        chainId: 11155111,
        rpc: process.env.SEPOLIA_RPC_URL || 'https://eth-sepolia.g.alchemy.com/v2/demo',
        explorer: 'https://sepolia.etherscan.io',
        color: 'cyan'
    },
    lasna: {
        name: 'Lasna (Reactive Network)',
        chainId: 5318007,
        rpc: process.env.REACTIVE_RPC_URL || 'https://lasna-rpc.rnk.dev/',
        explorer: 'https://lasna.rnk.dev',
        color: 'magenta'
    }
};

// ═══════════════════════════════════════════════════════════════
//                       CONTRACT ADDRESSES
// ═══════════════════════════════════════════════════════════════

export const CONTRACTS = {
    // Sepolia (Origin/Destination)
    manager: '0x188c7b7dC3EEbCA58371abC8D62cB62bEE201d47',
    callbackProxy: '0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA',
    funder: '0x9bcbE702215763e2D90BE8f3a374a41a32a0b791',
    
    // Lasna (Reactive Network)
    reactiveContract: '0xE58eA8c7eC0E47D195f720f34b3187F59eb27894',
    reactiveEnhanced: '0x5B8fEc5DBBE29d0B52141e51d407aDf8035bac3A',
    reactiveFunder: '0xa8D3bC8A55Cf854b3184C6bEaF09aE795De02ADC',
    systemContract: '0x0000000000000000000000000000000000fffFfF',
    
    // RVM IDs (deployer addresses)
    rvmId: '0x3a949910627c3D424d0871EFa2A34214293A5E25',
    deployerAddress: '0x3a949910627c3D424d0871EFa2A34214293A5E25'
};

// ═══════════════════════════════════════════════════════════════
//                         EVENT TOPICS
// ═══════════════════════════════════════════════════════════════

export const TOPICS = {
    // AutoLooperManager events
    PositionUpdated: '0xd97440db9c04f33925d0d4f3a9762d3e70c867b5d7e193cb11897e63c88f10de',
    LoopStepExecuted: '0xaff8ae41369611bef660d996b89b0ba1981219639194e3dfdc22bb20d88971ab',
    UnwindStepExecuted: '0x3c2c0c2d47ce56a6f6f98ca8c7abf6f5b5d4f5e6a7b8c9d0e1f2a3b4c5d6e7f8',
    PositionClosed: '0x4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d',
    
    // Callback event (IReactive)
    Callback: '0x8dd725fa9d6cd150017ab9e60318d40616439424e2fade9c1c58854950917dfc',
    
    // Subscribe event (System Contract)
    Subscribe: '0xe9b38458a3e5f63a0fc5d3466fbb6db53f5249ea82fc62c17c07e37936248f39',
    
    // AutoLooperReactive events
    LoopCallbackTriggered: '0xd2d51be9690a51552f9f38d2400c1b0d938b0290b24bdd3f7fbc2e871ea4be2f',
    UnwindCallbackTriggered: '0x6abb8987140c4823abbbe039dd31779ee288770b16bc1ca59de8f65d6904f99f'
};

// ═══════════════════════════════════════════════════════════════
//                         POSITION STATES
// ═══════════════════════════════════════════════════════════════

export const POSITION_STATES = {
    0: { name: 'IDLE', color: 'gray', emoji: '⚪' },
    1: { name: 'LOOPING', color: 'green', emoji: '🔄' },
    2: { name: 'UNWINDING', color: 'yellow', emoji: '⏪' },
    3: { name: 'EMERGENCY', color: 'red', emoji: '🚨' }
};

// ═══════════════════════════════════════════════════════════════
//                              ABIs
// ═══════════════════════════════════════════════════════════════

export const ABIS = {
    manager: [
        'event PositionUpdated(address indexed user, uint256 currentLeverage, uint256 targetLeverage, uint256 healthFactor, uint256 iteration, uint8 state)',
        'event LoopStepExecuted(address indexed user, uint256 borrowed, uint256 swapped, uint256 supplied, uint256 newLeverage)',
        'event UnwindStepExecuted(address indexed user, uint256 withdrawn, uint256 swapped, uint256 repaid, uint256 newLeverage)',
        'event PositionClosed(address indexed user, uint256 finalCollateral)',
        'event PositionCreated(address indexed user, address collateralAsset, address borrowAsset, uint256 targetLeverage)',
        'function deposit(address collateralAsset, address borrowAsset, uint256 amount, uint256 targetLeverage, uint256 maxIterations, bool useFlashLoan) payable',
        'function depositSameAsset(address asset, uint256 amount, uint256 targetLeverage, uint256 maxIterations) payable',
        'function getPosition(address user) view returns (tuple(address collateralAsset, address borrowAsset, uint256 initialCollateral, uint256 targetLeverage, uint256 currentLeverage, uint256 maxIterations, uint256 currentIteration, uint256 minHealthFactor, uint256 slippageTolerance, uint8 state, uint256 lastUpdateBlock, bool useFlashLoan, bool sameAssetLoop))',
        'function getHealthFactor(address user) view returns (uint256)',
        'function getCurrentLeverage(address user) view returns (uint256)',
        'function hasPosition(address user) view returns (bool)',
        'function loopFee() view returns (uint256)'
    ],
    reactive: [
        'event Callback(uint256 indexed chain_id, address indexed _contract, uint64 indexed gas_limit, bytes payload)',
        'event LoopCallbackTriggered(address indexed user, uint256 currentLeverage, uint256 targetLeverage)',
        'event UnwindCallbackTriggered(address indexed user, uint256 currentLeverage, uint256 healthFactor)'
    ],
    callbackProxy: [
        'function reserves(address) view returns (uint256)',
        'function depositTo(address rvm_id) payable'
    ]
};

// ═══════════════════════════════════════════════════════════════
//                       RNK RPC METHODS
// ═══════════════════════════════════════════════════════════════

export const RNK_METHODS = {
    getVm: 'rnk_getVm',
    getHeadNumber: 'rnk_getHeadNumber',
    getSubscribers: 'rnk_getSubscribers',
    getTransactions: 'rnk_getTransactions',
    getTransactionLogs: 'rnk_getTransactionLogs',
    getRnkAddressMapping: 'rnk_getRnkAddressMapping',
    getFilters: 'rnk_getFilters'
};

export default {
    NETWORKS,
    CONTRACTS,
    TOPICS,
    POSITION_STATES,
    ABIS,
    RNK_METHODS
};
