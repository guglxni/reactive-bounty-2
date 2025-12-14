// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractReactive} from "@reactive/abstract-base/AbstractReactive.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";
import {AbstractPayer} from "@reactive/abstract-base/AbstractPayer.sol";
import {IPayer} from "@reactive/interfaces/IPayer.sol";

/**
 * @title AutoLooperReactiveEnhanced
 * @notice Enhanced Reactive Smart Contract with advanced monitoring capabilities
 * @dev Implements patterns from Reactive Network blog articles:
 *      - Approval Magic (one-click deposit)
 *      - Uniswap Price Monitoring (stop-loss)
 *      - CRON Health Checks (periodic monitoring)
 *      - Multi-Event Subscriptions (comprehensive monitoring)
 * 
 * Architecture:
 * - Monitors PositionUpdated events from AutoLooperManager on Sepolia
 * - Monitors ERC20 Approval events for one-click deposit
 * - Monitors Uniswap V2 Sync events for price-based triggers
 * - Handles CRON events for periodic health checks
 * - Emits callbacks to execute loop/unwind/deposit steps based on events
 * 
 * Key Patterns:
 * - address(0) placeholder for RVM ID injection in callbacks
 * - vmOnly modifier for react() function
 * - rnOnly modifier for admin functions
 * - STATELESS design - all decisions from event data only
 */
contract AutoLooperReactiveEnhanced is IReactive, AbstractReactive {
    // ═══════════════════════════════════════════════════════════════
    //                         CONSTANTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice PositionUpdated event topic
    /// @dev keccak256("PositionUpdated(address,uint256,uint256,uint256,uint256,uint8)")
    uint256 private constant POSITION_UPDATED_TOPIC_0 = 
        0xd97440db9c04f33925d0d4f3a9762d3e70c867b5d7e193cb11897e63c88f10de;

    /// @notice ERC20 Approval event topic
    /// @dev keccak256("Approval(address,address,uint256)")
    uint256 private constant APPROVAL_TOPIC_0 = 
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    /// @notice Uniswap V2 Sync event topic
    /// @dev keccak256("Sync(uint112,uint112)")
    uint256 private constant SYNC_TOPIC_0 = 
        0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1;

    /// @notice Aave ReserveDataUpdated event topic
    /// @dev keccak256("ReserveDataUpdated(address,uint256,uint256,uint256,uint256,uint256)")
    uint256 private constant RESERVE_DATA_UPDATED_TOPIC_0 = 
        0x804c9b842b2748a22bb64b345453a3de7ca54a6ca45ce00d415894979e22897a;

    /// @notice Aave LiquidationCall event topic (for guardian failure tracking)
    /// @dev keccak256("LiquidationCall(address,address,address,uint256,uint256,address,bool)")
    uint256 private constant LIQUIDATION_CALL_TOPIC_0 = 
        0xe413a321e8681d831f4dbccbca790d2952b56f977908e45be37335533e005286;

    /// @notice CRON chain ID indicator (0 for CRON events)
    uint256 private constant CRON_CHAIN_ID = 0;

    /// @notice Callback gas limit (sufficient for loop/unwind operations)
    uint64 private constant CALLBACK_GAS_LIMIT = 1_000_000;

    /// @notice Higher gas limit for complex operations
    uint64 private constant HIGH_GAS_LIMIT = 1_500_000;

    /// @notice Minimum health factor threshold (1.1 = 1.1e18)
    uint256 private constant MIN_HEALTH_FACTOR = 1.1e18;

    /// @notice Precision for leverage calculations
    uint256 private constant PRECISION = 1e18;

    /// @notice Maximum loop iterations
    uint256 private constant MAX_ITERATIONS = 15;

    /// @notice Sepolia chain ID
    uint256 private constant SEPOLIA_CHAIN_ID = 11155111;

    /// @notice Position states (must match PositionState enum in Manager)
    uint8 private constant STATE_IDLE = 0;
    uint8 private constant STATE_LOOPING = 1;
    uint8 private constant STATE_UNWINDING = 2;
    uint8 private constant STATE_EMERGENCY = 3;

    /// @notice Price deviation threshold for emergency unwind (10% = 1000 bps)
    uint256 private constant PRICE_DEVIATION_THRESHOLD = 1000;
    uint256 private constant BPS = 10000;

    /// @notice Minimum approval amount to trigger auto-deposit (0.01 ether equivalent)
    uint256 private constant MIN_APPROVAL_AMOUNT = 0.01 ether;

    // ═══════════════════════════════════════════════════════════════
    //                         IMMUTABLES
    // ═══════════════════════════════════════════════════════════════

    /// @notice AutoLooperManager contract address on Sepolia
    address private immutable vault;

    /// @notice Destination chain ID
    uint256 private immutable chainId;

    // ═══════════════════════════════════════════════════════════════
    //                      CONFIGURATION STATE
    // ═══════════════════════════════════════════════════════════════

    /// @notice Owner address for admin functions
    address public owner;

    /// @notice Approval Magic enabled flag
    bool public approvalMagicEnabled = true;

    /// @notice Price monitoring enabled flag
    bool public priceMonitoringEnabled = true;

    /// @notice CRON monitoring enabled flag
    bool public cronMonitoringEnabled = true;

    /// @notice Tracked tokens for approval magic (token => enabled)
    mapping(address => bool) public trackedTokens;

    /// @notice Tracked Uniswap pools (pool => enabled)
    mapping(address => bool) public trackedPools;

    /// @notice Token to Uniswap pool mapping for price lookups
    mapping(address => address) public tokenToPools;

    /// @notice Last known price per pool (for deviation detection)
    mapping(address => uint256) public lastKnownPrices;

    /// @notice User price triggers for stop-loss (user => trigger price in 18 decimals)
    mapping(address => uint256) public userPriceTriggers;

    /// @notice User collateral tokens (user => token address)
    mapping(address => address) public userCollateralTokens;

    /// @notice Users with active positions for CRON batch checking
    address[] public activeUsers;
    mapping(address => bool) public isActiveUser;

    /// @notice CRON interval in blocks (e.g., 100 blocks ≈ 20 minutes on Sepolia)
    uint256 public cronInterval = 100;

    /// @notice User take-profit prices (user => take-profit price in 18 decimals)
    mapping(address => uint256) public userTakeProfitPrices;

    /// @notice Liquidation monitoring enabled flag
    bool public liquidationMonitoringEnabled = true;

    // ═══════════════════════════════════════════════════════════════
    //                   SUBSCRIPTION EXPIRY PATTERN (NFT SUB)
    // ═══════════════════════════════════════════════════════════════

    /// @notice Last check block per user (for stale position detection)
    mapping(address => uint256) public userLastCheckBlock;

    /// @notice Maximum blocks before position is considered stale (e.g., 1000 blocks ≈ 3.3 hours on Sepolia)
    uint256 public maxStaleBlocks = 1000;

    /// @notice Stale position check enabled flag
    bool public stalePositionCheckEnabled = true;

    // ═══════════════════════════════════════════════════════════════
    //                   FINALITY-AWARE CALLBACKS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Finality blocks required before critical operations (Reactive: ~64-95 blocks for 7.5-11 min)
    uint256 public constant FINALITY_BLOCKS = 64;

    /// @notice Pending critical operations awaiting finality
    mapping(bytes32 => uint256) public pendingOperationBlock;

    /// @notice Critical operation types
    enum CriticalOpType { EMERGENCY_UNWIND, LARGE_UNWIND, LIQUIDATION_RESPONSE }

    /// @notice Finality-aware mode enabled
    bool public finalityAwareEnabled = true;

    // ═══════════════════════════════════════════════════════════════
    //                      RATE LIMITING (RN State)
    // ═══════════════════════════════════════════════════════════════

    /// @notice Minimum blocks between callbacks for same user
    uint256 private constant MIN_BLOCKS_BETWEEN_CALLBACKS = 2;

    /// @notice Last callback block per user (RN state only)
    mapping(address => uint256) private lastCallbackBlock;

    // ═══════════════════════════════════════════════════════════════
    //                           EVENTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Emitted when a loop callback is triggered
    event LoopCallbackTriggered(address indexed user, uint256 currentLeverage, uint256 targetLeverage);

    /// @notice Emitted when an unwind callback is triggered
    event UnwindCallbackTriggered(address indexed user, uint256 currentLeverage, uint256 healthFactor);

    /// @notice Emitted when processing is skipped due to rate limiting
    event RateLimited(address indexed user, uint256 lastBlock, uint256 currentBlock);

    /// @notice Emitted when approval magic triggers auto-deposit
    event ApprovalMagicTriggered(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitted when price deviation triggers emergency action
    event PriceDeviationDetected(address indexed pool, uint256 oldPrice, uint256 newPrice, uint256 deviation);

    /// @notice Emitted when price stop-loss is triggered
    event StopLossTriggered(address indexed user, address indexed pool, uint256 currentPrice, uint256 triggerPrice);

    /// @notice Emitted when CRON health check is executed
    event CronHealthCheckExecuted(uint256 usersChecked, uint256 actionsTriggered);

    /// @notice Emitted when a new token is tracked for approval magic
    event TokenTracked(address indexed token);

    /// @notice Emitted when a Uniswap pool is tracked for price monitoring
    event PoolTracked(address indexed pool, address indexed token);

    /// @notice Emitted when user sets a price trigger
    event PriceTriggerSet(address indexed user, uint256 triggerPrice);

    /// @notice Emitted when reserve data change is detected
    event ReserveDataChanged(address indexed asset, uint256 liquidityRate, uint256 variableBorrowRate);

    /// @notice Emitted when take-profit is triggered
    event TakeProfitTriggered(address indexed user, address indexed pool, uint256 currentPrice, uint256 takeProfitPrice);

    /// @notice Emitted when user sets take-profit price
    event TakeProfitSet(address indexed user, uint256 takeProfitPrice);

    /// @notice Emitted when liquidation event is detected (guardian failure)
    event LiquidationDetected(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateral
    );

    /// @notice Emitted when a stale position is detected (NFT SUB pattern)
    event StalePositionDetected(address indexed user, uint256 lastCheckBlock, uint256 currentBlock, uint256 blocksSinceCheck);

    /// @notice Emitted when position check timestamp is updated
    event PositionCheckUpdated(address indexed user, uint256 blockNumber);

    /// @notice Emitted when critical operation is queued for finality
    event CriticalOperationQueued(bytes32 indexed opId, address indexed user, CriticalOpType opType, uint256 readyBlock);

    /// @notice Emitted when critical operation is executed after finality
    event CriticalOperationExecuted(bytes32 indexed opId, address indexed user, CriticalOpType opType);

    /// @notice Emitted when operation is rejected (finality not reached)
    event FinalityNotReached(bytes32 indexed opId, uint256 currentBlock, uint256 requiredBlock);

    // ═══════════════════════════════════════════════════════════════
    //                           ERRORS
    // ═══════════════════════════════════════════════════════════════

    error OnlyOwner();
    error ZeroAddress();
    error TokenAlreadyTracked();
    error PoolAlreadyTracked();
    error FinalityRequired();
    error OperationNotPending();

    // ═══════════════════════════════════════════════════════════════
    //                        MODIFIERS
    // ═══════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // ═══════════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the enhanced reactive contract
     * @param _vault AutoLooperManager address on destination chain
     * @param _chainId Destination chain ID (Sepolia = 11155111)
     */
    constructor(address _vault, uint256 _chainId) payable {
        if (_vault == address(0)) revert ZeroAddress();
        
        vault = _vault;
        chainId = _chainId;
        owner = msg.sender;
        
        // Subscribe to PositionUpdated events in constructor
        if (!vm) {
            service.subscribe(
                _chainId,                    // Chain ID to monitor (Sepolia)
                _vault,                      // Contract address to monitor (Manager)
                POSITION_UPDATED_TOPIC_0,    // topic_0 - event signature
                REACTIVE_IGNORE,             // topic_1 - ignore (user address is indexed)
                REACTIVE_IGNORE,             // topic_2 - ignore
                REACTIVE_IGNORE              // topic_3 - ignore
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                  SUBSCRIPTION MANAGEMENT
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Subscribe to PositionUpdated events from the Manager
     * @dev Backup method if constructor subscription needs refresh
     */
    function subscribeToManager() external rnOnly {
        service.subscribe(
            chainId,
            vault,
            POSITION_UPDATED_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /**
     * @notice Subscribe to ERC20 Approval events for one-click deposit
     * @dev Approval Magic pattern from GMP Comparison article
     * @param token The ERC20 token to monitor for approvals
     */
    function subscribeToApprovals(address token) external rnOnly onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (trackedTokens[token]) revert TokenAlreadyTracked();
        
        // Subscribe to Approval events where spender = vault (Manager)
        service.subscribe(
            chainId,
            token,
            APPROVAL_TOPIC_0,
            REACTIVE_IGNORE,               // topic_1 - owner (user) - any
            uint256(uint160(vault)),       // topic_2 - spender = Manager
            REACTIVE_IGNORE                // topic_3 - not used
        );
        
        trackedTokens[token] = true;
        emit TokenTracked(token);
    }

    /**
     * @notice Subscribe to Uniswap V2 Sync events for price monitoring
     * @dev ReacDEFI stop-loss pattern
     * @param pool The Uniswap V2 pair address to monitor
     * @param token The collateral token this pool represents
     */
    function subscribeToUniswapPool(address pool, address token) external rnOnly onlyOwner {
        if (pool == address(0) || token == address(0)) revert ZeroAddress();
        if (trackedPools[pool]) revert PoolAlreadyTracked();
        
        // Subscribe to Sync events from this pool
        service.subscribe(
            chainId,
            pool,
            SYNC_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        
        trackedPools[pool] = true;
        tokenToPools[token] = pool;
        emit PoolTracked(pool, token);
    }

    /**
     * @notice Subscribe to Aave ReserveDataUpdated events
     * @dev Multi-event subscription pattern for comprehensive monitoring
     * @param aavePool The Aave pool address to monitor
     */
    function subscribeToAaveReserves(address aavePool) external rnOnly onlyOwner {
        if (aavePool == address(0)) revert ZeroAddress();
        
        service.subscribe(
            chainId,
            aavePool,
            RESERVE_DATA_UPDATED_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /**
     * @notice Subscribe to Aave LiquidationCall events for guardian failure tracking
     * @dev Monitors if any of our users get liquidated (guardian failed to protect)
     *      Pattern from GMP Comparison "Liquidation Protection" section
     * @param aavePool The Aave pool address to monitor
     */
    function subscribeToLiquidations(address aavePool) external rnOnly onlyOwner {
        if (aavePool == address(0)) revert ZeroAddress();
        
        service.subscribe(
            chainId,
            aavePool,
            LIQUIDATION_CALL_TOPIC_0,
            REACTIVE_IGNORE, // collateralAsset
            REACTIVE_IGNORE, // debtAsset  
            REACTIVE_IGNORE  // user
        );
        
        liquidationMonitoringEnabled = true;
    }

    /**
     * @notice Subscribe to CRON events for periodic health checks
     * @dev NFT SUB pattern - blocks between checks
     * @param interval Block interval for CRON triggers
     */
    function subscribeToCron(uint256 interval) external rnOnly onlyOwner {
        cronInterval = interval;
        
        // CRON subscription: chain_id = 0 indicates CRON
        service.subscribe(
            CRON_CHAIN_ID,      // CRON indicator
            address(0),          // No specific contract
            interval,            // Block interval as topic_0
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        
        cronMonitoringEnabled = true;
    }

    /**
     * @notice Unsubscribe from CRON events
     */
    function unsubscribeFromCron() external rnOnly onlyOwner {
        bytes memory payload = abi.encodeWithSignature(
            "unsubscribe(uint256,address,uint256,uint256,uint256,uint256)",
            CRON_CHAIN_ID,
            address(0),
            cronInterval,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        (bool success,) = address(service).call(payload);
        require(success, "Unsubscribe failed");
        
        cronMonitoringEnabled = false;
    }

    // ═══════════════════════════════════════════════════════════════
    //                      REACT FUNCTION
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice React to various subscribed events
     * @dev Main entry point for all event processing
     *      Handles: PositionUpdated, Approval, Sync, CRON, ReserveDataUpdated
     * @param log The log record from the event
     */
    function react(IReactive.LogRecord calldata log) external override vmOnly {
        // Route based on event type
        
        // Check for CRON event (chain_id = 0)
        if (log.chain_id == CRON_CHAIN_ID && cronMonitoringEnabled) {
            _handleCronEvent();
            return;
        }

        // Check for PositionUpdated from Manager
        if (log._contract == vault && log.topic_0 == POSITION_UPDATED_TOPIC_0) {
            _handlePositionUpdated(log);
            return;
        }

        // Check for Approval event (Approval Magic)
        if (log.topic_0 == APPROVAL_TOPIC_0 && approvalMagicEnabled) {
            _handleApprovalEvent(log);
            return;
        }

        // Check for Uniswap Sync event (Price Monitoring)
        if (log.topic_0 == SYNC_TOPIC_0 && priceMonitoringEnabled) {
            _handleSyncEvent(log);
            return;
        }

        // Check for Aave ReserveDataUpdated event
        if (log.topic_0 == RESERVE_DATA_UPDATED_TOPIC_0) {
            _handleReserveDataUpdated(log);
            return;
        }

        // Check for Aave LiquidationCall event (guardian failure tracking)
        if (log.topic_0 == LIQUIDATION_CALL_TOPIC_0 && liquidationMonitoringEnabled) {
            _handleLiquidationEvent(log);
            return;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                 POSITION UPDATED HANDLING
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Handle PositionUpdated event from Manager
     * @param log The log record
     */
    function _handlePositionUpdated(IReactive.LogRecord calldata log) internal {
        // Extract user address from topic1 (indexed parameter)
        address user = address(uint160(log.topic_1));

        // Decode event data
        (
            uint256 currentLeverage,
            uint256 targetLeverage,
            uint256 healthFactor,
            uint256 iteration,
            uint8 state
        ) = abi.decode(log.data, (uint256, uint256, uint256, uint256, uint8));

        // Track active users for CRON checks
        _trackActiveUser(user, state);

        // Process based on state
        _processPositionUpdate(
            user,
            currentLeverage,
            targetLeverage,
            healthFactor,
            iteration,
            state
        );
    }

    /**
     * @notice Track active users for CRON batch processing
     */
    function _trackActiveUser(address user, uint8 state) internal {
        if (state != STATE_IDLE && !isActiveUser[user]) {
            activeUsers.push(user);
            isActiveUser[user] = true;
        } else if (state == STATE_IDLE && isActiveUser[user]) {
            // Remove from active users (expensive but necessary)
            isActiveUser[user] = false;
            // Note: We don't remove from array to save gas, just mark as inactive
        }
    }

    /**
     * @notice Process position update and emit appropriate callback
     */
    function _processPositionUpdate(
        address user,
        uint256 currentLeverage,
        uint256 targetLeverage,
        uint256 healthFactor,
        uint256 iteration,
        uint8 state
    ) internal {
        // Safety check: Emergency if health factor too low
        if (healthFactor < MIN_HEALTH_FACTOR && state != STATE_IDLE) {
            _emitUnwindCallback(user);
            emit UnwindCallbackTriggered(user, currentLeverage, healthFactor);
            return;
        }

        // Process based on state
        if (state == STATE_LOOPING) {
            _handleLoopingState(user, currentLeverage, targetLeverage, iteration);
        } else if (state == STATE_UNWINDING) {
            _handleUnwindingState(user, currentLeverage);
        } else if (state == STATE_EMERGENCY) {
            _handleEmergencyState(user, currentLeverage);
        }
    }

    function _handleLoopingState(
        address user,
        uint256 currentLeverage,
        uint256 targetLeverage,
        uint256 iteration
    ) internal {
        if (currentLeverage >= targetLeverage) {
            return; // Target reached
        }
        if (iteration >= MAX_ITERATIONS) {
            return; // Max iterations reached
        }

        _emitLoopCallback(user);
        emit LoopCallbackTriggered(user, currentLeverage, targetLeverage);
    }

    function _handleUnwindingState(address user, uint256 currentLeverage) internal {
        if (currentLeverage <= PRECISION) {
            return; // Fully unwound
        }
        _emitUnwindCallback(user);
    }

    function _handleEmergencyState(address user, uint256 currentLeverage) internal {
        if (currentLeverage <= PRECISION) {
            return;
        }
        _emitUnwindCallback(user);
    }

    // ═══════════════════════════════════════════════════════════════
    //                   APPROVAL MAGIC HANDLING
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Handle ERC20 Approval event for one-click deposit
     * @dev When user approves tokens to Manager, auto-trigger deposit
     *      Pattern from GMP Comparison "Approval Magic" demo
     * @param log The log record containing Approval event
     */
    function _handleApprovalEvent(IReactive.LogRecord calldata log) internal {
        // Verify this is from a tracked token
        if (!trackedTokens[log._contract]) {
            return;
        }

        // Extract parameters from indexed topics
        // topic_1 = owner (user who approved)
        // topic_2 = spender (should be vault/Manager)
        address user = address(uint160(log.topic_1));
        address spender = address(uint160(log.topic_2));

        // Verify spender is our Manager
        if (spender != vault) {
            return;
        }

        // Decode amount from data
        uint256 amount = abi.decode(log.data, (uint256));

        // Skip if amount is too small or zero (revocation)
        if (amount < MIN_APPROVAL_AMOUNT) {
            return;
        }

        // Emit callback to auto-deposit
        emit ApprovalMagicTriggered(user, log._contract, amount);
        _emitApprovalDepositCallback(user, log._contract, amount);
    }

    /**
     * @notice Emit callback to execute auto-deposit after approval
     * @param user The user who approved
     * @param token The token that was approved
     * @param amount The approved amount
     */
    function _emitApprovalDepositCallback(address user, address token, uint256 amount) internal {
        bytes memory payload = abi.encodeWithSignature(
            "executeApprovalDeposit(address,address,address,uint256)",
            address(0), // RVM ID placeholder
            user,
            token,
            amount
        );

        emit Callback(
            chainId,
            vault,
            HIGH_GAS_LIMIT,
            payload
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                   PRICE MONITORING (SYNC)
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Handle Uniswap V2 Sync event for price monitoring
     * @dev ReacDEFI stop-loss pattern
     * @param log The log record containing Sync event
     */
    function _handleSyncEvent(IReactive.LogRecord calldata log) internal {
        // Verify this is from a tracked pool
        if (!trackedPools[log._contract]) {
            return;
        }

        // Decode reserves from data
        // Sync(uint112 reserve0, uint112 reserve1)
        (uint112 reserve0, uint112 reserve1) = abi.decode(log.data, (uint112, uint112));

        // Calculate price (reserve1 / reserve0) with 18 decimals
        // Assumes token0 is the collateral token
        uint256 currentPrice = reserve1 > 0 && reserve0 > 0 
            ? (uint256(reserve1) * PRECISION) / uint256(reserve0)
            : 0;

        if (currentPrice == 0) {
            return;
        }

        address pool = log._contract;
        uint256 oldPrice = lastKnownPrices[pool];

        // Update stored price
        lastKnownPrices[pool] = currentPrice;

        // Skip if this is the first price update
        if (oldPrice == 0) {
            return;
        }

        // Calculate price deviation
        uint256 deviation;
        if (currentPrice > oldPrice) {
            deviation = ((currentPrice - oldPrice) * BPS) / oldPrice;
        } else {
            deviation = ((oldPrice - currentPrice) * BPS) / oldPrice;
        }

        // If significant deviation, emit event for monitoring
        if (deviation >= PRICE_DEVIATION_THRESHOLD) {
            emit PriceDeviationDetected(pool, oldPrice, currentPrice, deviation);
            // Trigger batch check for all users with this collateral
            _checkPriceTriggeredUnwinds(pool, currentPrice);
        }
    }

    /**
     * @notice Check if any users have stop-loss triggers at current price
     * @param pool The Uniswap pool that had price change
     * @param currentPrice Current price from Sync event
     */
    function _checkPriceTriggeredUnwinds(address pool, uint256 currentPrice) internal {
        // Check all active users
        for (uint256 i = 0; i < activeUsers.length; i++) {
            address user = activeUsers[i];
            
            // Skip inactive users
            if (!isActiveUser[user]) {
                continue;
            }

            // Check if user has a price trigger for this pool's token
            address userToken = userCollateralTokens[user];
            if (tokenToPools[userToken] != pool) {
                continue;
            }

            // Check if price is below stop-loss trigger
            uint256 stopLossPrice = userPriceTriggers[user];
            if (stopLossPrice > 0 && currentPrice < stopLossPrice) {
                emit StopLossTriggered(user, pool, currentPrice, stopLossPrice);
                _emitPriceTriggeredUnwindCallback(user);
                continue; // Don't check take-profit if stop-loss triggered
            }

            // Check if price is above take-profit trigger
            uint256 takeProfitPrice = userTakeProfitPrices[user];
            if (takeProfitPrice > 0 && currentPrice >= takeProfitPrice) {
                emit TakeProfitTriggered(user, pool, currentPrice, takeProfitPrice);
                _emitTakeProfitCallback(user, currentPrice);
            }
        }
    }

    /**
     * @notice Emit callback to trigger take-profit unwind
     */
    function _emitTakeProfitCallback(address user, uint256 currentPrice) internal {
        bytes memory payload = abi.encodeWithSignature(
            "executeTakeProfit(address,address,uint256)",
            address(0), // RVM ID placeholder
            user,
            currentPrice
        );

        emit Callback(
            chainId,
            vault,
            CALLBACK_GAS_LIMIT,
            payload
        );
    }

    /**
     * @notice Check take-profit triggers during CRON for all active users
     * @dev Called during CRON health check phase
     */
    function _checkTakeProfitTriggers() internal {
        for (uint256 i = 0; i < activeUsers.length; i++) {
            address user = activeUsers[i];
            if (!isActiveUser[user]) continue;
            
            uint256 takeProfitPrice = userTakeProfitPrices[user];
            if (takeProfitPrice == 0) continue; // No take-profit set
            
            // Get user's collateral token and pool
            address token = userCollateralTokens[user];
            if (token == address(0)) continue;
            
            address pool = tokenToPools[token];
            if (pool == address(0)) continue;
            
            uint256 currentPrice = lastKnownPrices[pool];
            if (currentPrice == 0) continue;
            
            // Check if current price >= take-profit target
            if (currentPrice >= takeProfitPrice) {
                emit TakeProfitTriggered(user, pool, currentPrice, takeProfitPrice);
                _emitTakeProfitCallback(user, currentPrice);
            }
        }
    }

    /**
     * @notice Emit callback to trigger price-based emergency unwind
     */
    function _emitPriceTriggeredUnwindCallback(address user) internal {
        bytes memory payload = abi.encodeWithSignature(
            "executePriceTriggeredUnwind(address,address)",
            address(0), // RVM ID placeholder
            user
        );

        emit Callback(
            chainId,
            vault,
            CALLBACK_GAS_LIMIT,
            payload
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                    CRON HEALTH CHECKS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Handle CRON event for periodic health checks
     * @dev NFT SUB pattern - batch process all active positions
     *      Enhanced with: stale position detection, finality-aware callbacks
     */
    function _handleCronEvent() internal {
        if (!cronMonitoringEnabled) {
            return;
        }

        uint256 actionsTriggered = 0;
        uint256 usersChecked = 0;
        uint256 maxBatch = 50; // Process up to 50 users per CRON

        // Phase 1: Check stale positions first (NFT SUB expiry pattern)
        uint256 staleCount = _checkStalePositions();
        actionsTriggered += staleCount;

        // Phase 2: Regular health checks for remaining capacity
        uint256 remainingCapacity = maxBatch > staleCount ? maxBatch - staleCount : 0;

        for (uint256 i = 0; i < activeUsers.length && usersChecked < remainingCapacity; i++) {
            address user = activeUsers[i];
            
            if (!isActiveUser[user]) {
                continue;
            }

            // Skip if we already checked this user as stale
            (bool isStale,) = isPositionStale(user);
            if (isStale) {
                continue; // Already handled in Phase 1
            }

            usersChecked++;

            // Emit callback to check and potentially unwind this user
            _emitHealthCheckCallback(user);
            _updateUserCheckTimestamp(user);
            actionsTriggered++;
        }

        // Phase 3: Check take-profit triggers during CRON
        _checkTakeProfitTriggers();

        emit CronHealthCheckExecuted(usersChecked + staleCount, actionsTriggered);
    }

    /**
     * @notice Emit callback for CRON-based health check
     */
    function _emitHealthCheckCallback(address user) internal {
        bytes memory payload = abi.encodeWithSignature(
            "executeHealthCheck(address,address)",
            address(0), // RVM ID placeholder
            user
        );

        emit Callback(
            chainId,
            vault,
            CALLBACK_GAS_LIMIT,
            payload
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                   RESERVE DATA HANDLING
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Handle Aave ReserveDataUpdated event
     * @dev Multi-event subscription pattern
     * @param log The log record
     */
    function _handleReserveDataUpdated(IReactive.LogRecord calldata log) internal {
        // Decode reserve data
        // ReserveDataUpdated(address indexed asset, uint256 liquidityRate, uint256 stableBorrowRate, 
        //                    uint256 variableBorrowRate, uint256 liquidityIndex, uint256 variableBorrowIndex)
        address asset = address(uint160(log.topic_1));
        
        (
            uint256 liquidityRate,
            ,  // stableBorrowRate - not used
            uint256 variableBorrowRate,
            ,  // liquidityIndex - not used
               // variableBorrowIndex - not used
        ) = abi.decode(log.data, (uint256, uint256, uint256, uint256, uint256));

        emit ReserveDataChanged(asset, liquidityRate, variableBorrowRate);

        // If borrow rate spikes significantly, could trigger protective unwinds
        // This is informational for now - could add threshold-based actions
    }

    // ═══════════════════════════════════════════════════════════════
    //                   LIQUIDATION MONITORING
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Handle Aave LiquidationCall event for guardian failure tracking
     * @dev This should never be called if our health guardian is working properly
     *      Pattern from GMP Comparison "Liquidation Protection" section
     * @param log The log record containing LiquidationCall event
     */
    function _handleLiquidationEvent(IReactive.LogRecord calldata log) internal {
        // LiquidationCall(address indexed collateralAsset, address indexed debtAsset, 
        //                 address indexed user, uint256 debtToCover, uint256 liquidatedCollateral, 
        //                 address liquidator, bool receiveAToken)
        address collateralAsset = address(uint160(log.topic_1));
        address debtAsset = address(uint160(log.topic_2));
        address user = address(uint160(log.topic_3));
        
        // Decode non-indexed parameters
        (uint256 debtToCover, uint256 liquidatedCollateral, , ) = 
            abi.decode(log.data, (uint256, uint256, address, bool));
        
        // Check if this was one of our tracked users
        if (!isActiveUser[user]) {
            return; // Not our user, ignore
        }
        
        // This is a guardian failure - emit event for analytics
        emit LiquidationDetected(collateralAsset, debtAsset, user, debtToCover, liquidatedCollateral);
        
        // Emit callback to Manager for failure tracking
        _emitLiquidationCallback(user, debtToCover);
    }

    /**
     * @notice Emit callback to notify Manager of liquidation (guardian failure)
     */
    function _emitLiquidationCallback(address user, uint256 debtCovered) internal {
        bytes memory payload = abi.encodeWithSignature(
            "executeLiquidationCallback(address,address,uint256)",
            address(0), // RVM ID placeholder
            user,
            debtCovered
        );

        emit Callback(
            chainId,
            vault,
            CALLBACK_GAS_LIMIT,
            payload
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                     CALLBACK EMISSION
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Emit callback to execute next loop step
     */
    function _emitLoopCallback(address user) internal {
        bytes memory payload = abi.encodeWithSignature(
            "executeLoopStep(address,address)",
            address(0), // Placeholder - will be replaced with RVM ID by network
            user
        );

        emit Callback(
            chainId,
            vault,
            CALLBACK_GAS_LIMIT,
            payload
        );
    }

    /**
     * @notice Emit callback to execute unwind step
     */
    function _emitUnwindCallback(address user) internal {
        bytes memory payload = abi.encodeWithSignature(
            "executeUnwindStep(address,address)",
            address(0), // Placeholder - will be replaced with RVM ID by network
            user
        );

        emit Callback(
            chainId,
            vault,
            CALLBACK_GAS_LIMIT,
            payload
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                      USER CONFIGURATION
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Set user's collateral token for price monitoring
     * @param user The user address
     * @param token The collateral token address
     */
    function setUserCollateralToken(address user, address token) external rnOnly {
        userCollateralTokens[user] = token;
    }

    /**
     * @notice Set user's price trigger for stop-loss
     * @param user The user address
     * @param triggerPrice The price below which to trigger unwind (18 decimals)
     */
    function setUserPriceTrigger(address user, uint256 triggerPrice) external rnOnly {
        userPriceTriggers[user] = triggerPrice;
        emit PriceTriggerSet(user, triggerPrice);
    }

    /**
     * @notice Set user's take-profit price trigger
     * @param user The user address
     * @param takeProfitPrice The price above which to take profit (18 decimals)
     */
    function setUserTakeProfitPrice(address user, uint256 takeProfitPrice) external rnOnly {
        userTakeProfitPrices[user] = takeProfitPrice;
        emit TakeProfitSet(user, takeProfitPrice);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Toggle Approval Magic feature
     */
    function setApprovalMagicEnabled(bool enabled) external rnOnly onlyOwner {
        approvalMagicEnabled = enabled;
    }

    /**
     * @notice Toggle Price Monitoring feature
     */
    function setPriceMonitoringEnabled(bool enabled) external rnOnly onlyOwner {
        priceMonitoringEnabled = enabled;
    }

    /**
     * @notice Toggle CRON Monitoring feature
     */
    function setCronMonitoringEnabled(bool enabled) external rnOnly onlyOwner {
        cronMonitoringEnabled = enabled;
    }

    /**
     * @notice Toggle Liquidation Monitoring feature
     */
    function setLiquidationMonitoringEnabled(bool enabled) external rnOnly onlyOwner {
        liquidationMonitoringEnabled = enabled;
    }

    /**
     * @notice Pause the reactive contract
     */
    function pause() external rnOnly onlyOwner {
        bytes memory payload = abi.encodeWithSignature(
            "unsubscribe(uint256,address,uint256,uint256,uint256,uint256)",
            chainId,
            vault,
            POSITION_UPDATED_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        (bool success,) = address(service).call(payload);
        require(success, "Unsubscribe failed");
    }

    /**
     * @notice Resume the reactive contract
     */
    function resume() external rnOnly onlyOwner {
        bytes memory payload = abi.encodeWithSignature(
            "subscribe(uint256,address,uint256,uint256,uint256,uint256)",
            chainId,
            vault,
            POSITION_UPDATED_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        (bool success,) = address(service).call(payload);
        require(success, "Subscribe failed");
    }

    /**
     * @notice Transfer ownership
     */
    function transferOwnership(address newOwner) external rnOnly onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    // ═══════════════════════════════════════════════════════════════
    //                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    function getVault() external view returns (address) {
        return vault;
    }

    function getChainId() external view returns (uint256) {
        return chainId;
    }

    function getActiveUsersCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < activeUsers.length; i++) {
            if (isActiveUser[activeUsers[i]]) {
                count++;
            }
        }
        return count;
    }

    function getActiveUsers() external view returns (address[] memory) {
        return activeUsers;
    }

    function getUserPriceTrigger(address user) external view returns (uint256) {
        return userPriceTriggers[user];
    }

    function getUserTakeProfitPrice(address user) external view returns (uint256) {
        return userTakeProfitPrices[user];
    }

    function getPoolPrice(address pool) external view returns (uint256) {
        return lastKnownPrices[pool];
    }

    // ═══════════════════════════════════════════════════════════════
    //              SUBSCRIPTION EXPIRY PATTERN (NFT SUB)
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Update user's last check block (called when position is checked)
     * @dev NFT SUB pattern - tracks when positions were last monitored
     * @param user The user whose check timestamp to update
     */
    function _updateUserCheckTimestamp(address user) internal {
        userLastCheckBlock[user] = block.number;
        emit PositionCheckUpdated(user, block.number);
    }

    /**
     * @notice Check if a position is stale (not checked recently)
     * @param user The user to check
     * @return isStale True if position hasn't been checked in maxStaleBlocks
     * @return blocksSinceCheck Number of blocks since last check
     */
    function isPositionStale(address user) public view returns (bool isStale, uint256 blocksSinceCheck) {
        uint256 lastCheck = userLastCheckBlock[user];
        if (lastCheck == 0) {
            // Never checked - consider stale if user is active
            return (isActiveUser[user], block.number);
        }
        blocksSinceCheck = block.number - lastCheck;
        isStale = blocksSinceCheck > maxStaleBlocks;
    }

    /**
     * @notice Process stale positions during CRON (NFT SUB batch pattern)
     * @dev Called as part of CRON health check to prioritize stale positions
     */
    function _checkStalePositions() internal returns (uint256 staleCount) {
        if (!stalePositionCheckEnabled) return 0;

        uint256 maxBatch = 25; // Check up to 25 stale positions per CRON
        staleCount = 0;

        for (uint256 i = 0; i < activeUsers.length && staleCount < maxBatch; i++) {
            address user = activeUsers[i];
            if (!isActiveUser[user]) continue;

            (bool isStale, uint256 blocksSince) = isPositionStale(user);
            
            if (isStale) {
                emit StalePositionDetected(user, userLastCheckBlock[user], block.number, blocksSince);
                
                // Emit high-priority health check callback for stale position
                _emitHealthCheckCallback(user);
                _updateUserCheckTimestamp(user);
                staleCount++;
            }
        }
    }

    /**
     * @notice Set maximum blocks before position is considered stale
     * @param _maxStaleBlocks New stale threshold in blocks
     */
    function setMaxStaleBlocks(uint256 _maxStaleBlocks) external rnOnly onlyOwner {
        maxStaleBlocks = _maxStaleBlocks;
    }

    /**
     * @notice Enable/disable stale position checking
     */
    function setStalePositionCheckEnabled(bool enabled) external rnOnly onlyOwner {
        stalePositionCheckEnabled = enabled;
    }

    // ═══════════════════════════════════════════════════════════════
    //                   FINALITY-AWARE CALLBACKS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Queue a critical operation that requires finality confirmation
     * @dev From Performance Race: Finality article - wait for economic finality
     * @param user The user involved in the operation
     * @param opType The type of critical operation
     * @return opId The unique operation ID
     */
    function _queueCriticalOperation(
        address user,
        CriticalOpType opType
    ) internal returns (bytes32 opId) {
        opId = keccak256(abi.encodePacked(user, opType, block.number, block.timestamp));
        pendingOperationBlock[opId] = block.number;
        
        uint256 readyBlock = block.number + FINALITY_BLOCKS;
        emit CriticalOperationQueued(opId, user, opType, readyBlock);
    }

    /**
     * @notice Check if a critical operation has reached finality
     * @param opId The operation ID to check
     * @return ready True if finality has been reached
     * @return blocksRemaining Blocks until finality (0 if ready)
     */
    function isCriticalOperationReady(bytes32 opId) public view returns (bool ready, uint256 blocksRemaining) {
        uint256 queuedBlock = pendingOperationBlock[opId];
        if (queuedBlock == 0) {
            return (false, 0); // Not pending
        }
        
        uint256 readyBlock = queuedBlock + FINALITY_BLOCKS;
        if (block.number >= readyBlock) {
            return (true, 0);
        }
        
        blocksRemaining = readyBlock - block.number;
        return (false, blocksRemaining);
    }

    /**
     * @notice Execute a critical operation after finality (or immediately if disabled)
     * @param opId The operation ID
     * @param user The user involved
     * @param opType The operation type
     */
    function _executeCriticalOperation(
        bytes32 opId,
        address user,
        CriticalOpType opType
    ) internal {
        if (finalityAwareEnabled) {
            (bool ready, uint256 remaining) = isCriticalOperationReady(opId);
            if (!ready) {
                emit FinalityNotReached(opId, block.number, block.number + remaining);
                return; // Skip for now, will retry on next CRON
            }
        }

        // Clear pending status
        delete pendingOperationBlock[opId];
        
        // Execute based on operation type
        if (opType == CriticalOpType.EMERGENCY_UNWIND) {
            _emitEmergencyUnwindCallback(user);
        } else if (opType == CriticalOpType.LARGE_UNWIND) {
            _emitUnwindCallback(user);
        } else if (opType == CriticalOpType.LIQUIDATION_RESPONSE) {
            _emitHealthCheckCallback(user);
        }
        
        emit CriticalOperationExecuted(opId, user, opType);
    }

    /**
     * @notice Emit emergency unwind callback (for finality-aware operations)
     */
    function _emitEmergencyUnwindCallback(address user) internal {
        bytes memory payload = abi.encodeWithSignature(
            "executeEmergencyUnwind(address,address)",
            address(0), // RVM ID placeholder
            user
        );

        emit Callback(
            chainId,
            vault,
            HIGH_GAS_LIMIT,
            payload
        );
    }

    /**
     * @notice Enable/disable finality-aware mode
     */
    function setFinalityAwareEnabled(bool enabled) external rnOnly onlyOwner {
        finalityAwareEnabled = enabled;
    }

    /**
     * @notice Get pending operation details
     */
    function getPendingOperation(bytes32 opId) external view returns (uint256 queuedBlock, bool ready, uint256 blocksRemaining) {
        queuedBlock = pendingOperationBlock[opId];
        (ready, blocksRemaining) = isCriticalOperationReady(opId);
    }

    // ═══════════════════════════════════════════════════════════════
    //                      RECEIVE ETH
    // ═══════════════════════════════════════════════════════════════

    receive() external payable override(AbstractPayer, IPayer) {}
}
