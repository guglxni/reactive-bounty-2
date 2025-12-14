/**
 * Logger utility for Reactive Auto-Looper Monitor
 * 
 * Provides colored, timestamped, structured logging
 */

import chalk from 'chalk';

// ═══════════════════════════════════════════════════════════════
//                         LOG LEVELS
// ═══════════════════════════════════════════════════════════════

const LOG_LEVELS = {
    DEBUG: { priority: 0, color: chalk.gray, prefix: '🔍' },
    INFO: { priority: 1, color: chalk.blue, prefix: 'ℹ️ ' },
    EVENT: { priority: 2, color: chalk.cyan, prefix: '📡' },
    SUCCESS: { priority: 3, color: chalk.green, prefix: '✅' },
    WARN: { priority: 4, color: chalk.yellow, prefix: '⚠️ ' },
    ERROR: { priority: 5, color: chalk.red, prefix: '❌' },
    CRITICAL: { priority: 6, color: chalk.bgRed.white, prefix: '🚨' }
};

let currentLogLevel = 1; // INFO by default

// ═══════════════════════════════════════════════════════════════
//                       NETWORK COLORS
// ═══════════════════════════════════════════════════════════════

const NETWORK_COLORS = {
    sepolia: chalk.cyan,
    lasna: chalk.magenta,
    rvm: chalk.yellow
};

// ═══════════════════════════════════════════════════════════════
//                       FORMAT HELPERS
// ═══════════════════════════════════════════════════════════════

function timestamp() {
    return chalk.gray(`[${new Date().toISOString()}]`);
}

function networkTag(network) {
    const color = NETWORK_COLORS[network] || chalk.white;
    return color(`[${network.toUpperCase()}]`);
}

function truncateAddress(address, chars = 6) {
    if (!address) return 'N/A';
    return `${address.slice(0, chars + 2)}...${address.slice(-chars)}`;
}

function formatEth(wei) {
    if (!wei) return '0 ETH';
    const eth = Number(wei) / 1e18;
    return `${eth.toFixed(6)} ETH`;
}

function formatLeverage(leverage) {
    if (!leverage) return '0x';
    const lev = Number(leverage) / 1e18;
    return `${lev.toFixed(2)}x`;
}

// ═══════════════════════════════════════════════════════════════
//                       MAIN LOG FUNCTION
// ═══════════════════════════════════════════════════════════════

function log(level, message, data = null, network = null) {
    const logConfig = LOG_LEVELS[level] || LOG_LEVELS.INFO;
    
    if (logConfig.priority < currentLogLevel) return;
    
    const parts = [
        timestamp(),
        logConfig.prefix,
        network ? networkTag(network) : '',
        logConfig.color(message)
    ].filter(Boolean);
    
    console.log(parts.join(' '));
    
    if (data) {
        if (typeof data === 'object') {
            Object.entries(data).forEach(([key, value]) => {
                console.log(chalk.gray(`    ${key}: ${chalk.white(value)}`));
            });
        } else {
            console.log(chalk.gray(`    ${data}`));
        }
    }
}

// ═══════════════════════════════════════════════════════════════
//                    SPECIALIZED LOGGERS
// ═══════════════════════════════════════════════════════════════

export const logger = {
    setLevel(level) {
        currentLogLevel = LOG_LEVELS[level]?.priority ?? 1;
    },
    
    debug(msg, data, network) { log('DEBUG', msg, data, network); },
    info(msg, data, network) { log('INFO', msg, data, network); },
    event(msg, data, network) { log('EVENT', msg, data, network); },
    success(msg, data, network) { log('SUCCESS', msg, data, network); },
    warn(msg, data, network) { log('WARN', msg, data, network); },
    error(msg, data, network) { log('ERROR', msg, data, network); },
    critical(msg, data, network) { log('CRITICAL', msg, data, network); },
    
    // Event-specific loggers
    positionUpdated(user, data) {
        console.log('');
        console.log(chalk.bgGreen.black(' POSITION UPDATED '));
        console.log(chalk.green(`  User: ${user}`));
        console.log(chalk.green(`  Current Leverage: ${formatLeverage(data.currentLeverage)}`));
        console.log(chalk.green(`  Target Leverage: ${formatLeverage(data.targetLeverage)}`));
        console.log(chalk.green(`  Health Factor: ${data.healthFactor}`));
        console.log(chalk.green(`  Iteration: ${data.iteration}`));
        console.log(chalk.green(`  State: ${data.state}`));
        console.log('');
    },
    
    callbackEmitted(chainId, contract, gasLimit, payloadPreview) {
        console.log('');
        console.log(chalk.bgYellow.black(' CALLBACK EMITTED '));
        console.log(chalk.yellow(`  Chain ID: ${chainId}`));
        console.log(chalk.yellow(`  Target: ${truncateAddress(contract)}`));
        console.log(chalk.yellow(`  Gas Limit: ${gasLimit}`));
        console.log(chalk.yellow(`  Payload: ${payloadPreview}`));
        console.log('');
    },
    
    rvmTransaction(txNum, data) {
        console.log('');
        console.log(chalk.bgMagenta.white(' RVM TRANSACTION '));
        console.log(chalk.magenta(`  TX #: ${txNum}`));
        console.log(chalk.magenta(`  Status: ${data.status === 1 ? '✅ Success' : '❌ Failed'}`));
        console.log(chalk.magenta(`  Gas Used: ${data.used}`));
        console.log(chalk.magenta(`  Ref Chain: ${data.refChainId}`));
        console.log(chalk.magenta(`  Ref TX: ${truncateAddress(data.refTx)}`));
        console.log('');
    },
    
    separator() {
        console.log(chalk.gray('─'.repeat(60)));
    },
    
    header(title) {
        console.log('');
        console.log(chalk.bgBlue.white(` ${title} `));
        console.log('');
    },
    
    subheader(title) {
        console.log(chalk.yellow(title));
        console.log(chalk.gray('─'.repeat(50)));
    },
    
    warning(msg, data, network) { log('WARN', msg, data, network); },
    pending(msg) {
        console.log(chalk.gray(`⏳ ${msg}`));
    },
    
    // Helper functions exposed
    truncateAddress,
    formatEth,
    formatLeverage
};

export default logger;
