// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAutoLooper
 * @notice Interface for the AutoLooper system
 */

/// @notice Position states for the looping system
enum PositionState {
    IDLE,       // 0 - No active position or completed
    LOOPING,    // 1 - Actively looping to increase leverage
    UNWINDING,  // 2 - User-requested unwind in progress
    EMERGENCY   // 3 - Emergency unwind due to health factor
}

/// @notice User position data structure
struct UserPosition {
    // Asset configuration
    address collateralAsset;      // Token used as collateral (e.g., WETH)
    address borrowAsset;          // Token to borrow (e.g., USDC, or same as collateral)
    
    // Position parameters
    uint256 initialCollateral;    // Original deposit amount
    uint256 targetLeverage;       // Target leverage (18 decimals, e.g., 3e18 = 3x)
    uint256 currentLeverage;      // Current leverage (18 decimals)
    uint256 maxIterations;        // Maximum loop iterations allowed
    uint256 currentIteration;     // Current iteration count
    
    // Safety parameters
    uint256 minHealthFactor;      // Minimum health factor to maintain (18 decimals)
    uint256 slippageTolerance;    // Max slippage for swaps (basis points, e.g., 50 = 0.5%)
    
    // State
    PositionState state;          // Current position state
    uint256 lastUpdateBlock;      // Block number of last update
    
    // Flash loan mode
    bool useFlashLoan;            // Use flash loan for instant leverage
    
    // Same-asset loop mode (no swaps needed - bypasses DEX liquidity)
    bool sameAssetLoop;           // If true, borrow same asset as collateral (no swap)
    
    // Gas budget tracking (Advanced Feature)
    uint256 maxGasSpend;          // Maximum gas budget for this position (0 = unlimited)
    uint256 gasSpentSoFar;        // Cumulative gas spent on this position
    
    // TWAP execution (Advanced Feature for large positions)
    uint256 twapBlockInterval;    // Minimum blocks between steps (0 = no TWAP)
    
    // MEV protection (Advanced Feature)
    bytes32 executionSalt;        // Salt for unpredictable execution verification
    
    // Take-profit / Stop-loss triggers (Limit Order Style Unwind)
    uint256 takeProfitPrice;      // Price above which to take profit (18 decimals, 0 = disabled)
    uint256 stopLossPrice;        // Price below which to stop loss (18 decimals, 0 = disabled)
}

/// @notice Take-profit/Stop-loss configuration
struct TakeProfitConfig {
    uint256 takeProfitPrice;      // Unwind if collateral price reaches this (0 = disabled)
    uint256 stopLossPrice;        // Unwind if collateral price drops below this (0 = disabled)
}

/// @notice Advanced position configuration
struct AdvancedConfig {
    uint256 maxGasSpend;          // Maximum gas budget (0 = unlimited)
    uint256 twapBlockInterval;    // Blocks between steps for large positions (0 = disabled)
    bool enableMevProtection;     // Enable MEV protection features
    bool checkProfitability;      // Only loop when profitable (APY check)
}

interface IAutoLooper {
    // ═══════════════════════════════════════════════════════════════
    //                           EVENTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Emitted when a position is updated (primary event for RSC)
    event PositionUpdated(
        address indexed user,
        uint256 currentLeverage,
        uint256 targetLeverage,
        uint256 healthFactor,
        uint256 iteration,
        PositionState state
    );

    /// @notice Emitted when a loop step is executed
    event LoopStepExecuted(
        address indexed user,
        uint256 borrowed,
        uint256 swapped,
        uint256 supplied,
        uint256 newLeverage
    );

    /// @notice Emitted when an unwind step is executed
    event UnwindStepExecuted(
        address indexed user,
        uint256 withdrawn,
        uint256 swapped,
        uint256 repaid,
        uint256 newLeverage
    );

    /// @notice Emitted when flash leverage is executed
    event FlashLeverageExecuted(
        address indexed user,
        uint256 flashAmount,
        uint256 finalLeverage
    );

    /// @notice Emitted when flash unwind is executed
    event FlashUnwindExecuted(
        address indexed user,
        uint256 flashAmount,
        uint256 finalLeverage
    );

    /// @notice Emitted when a position is created
    event PositionCreated(
        address indexed user,
        address collateralAsset,
        address borrowAsset,
        uint256 targetLeverage
    );

    /// @notice Emitted when a position is closed
    event PositionClosed(address indexed user, uint256 finalCollateral);

    /// @notice Emitted on emergency stop
    event EmergencyStop(address indexed user, string reason);

    /// @notice Emitted when circuit breaker triggers
    event CircuitBreakerTriggered(address indexed user, uint256 deviation);

    /// @notice Emitted when reactive gas is refilled
    event GasRefilled(address indexed reactiveContract, uint256 amount);

    /// @notice Emitted when RVM ID is updated
    event RvmIdUpdated(address indexed rvmId);

    /// @notice Emitted when gas budget is exceeded
    event GasBudgetExceeded(address indexed user, uint256 gasSpent, uint256 maxGas);

    /// @notice Emitted when APY check determines looping is unprofitable
    event LoopUnprofitable(address indexed user, uint256 supplyAPY, uint256 borrowAPY);

    /// @notice Emitted when TWAP interval restricts execution
    event TwapIntervalNotMet(address indexed user, uint256 lastBlock, uint256 currentBlock, uint256 requiredInterval);

    /// @notice Emitted when MEV protection salt is invalid
    event MevProtectionTriggered(address indexed user, bytes32 expectedSalt, bytes32 providedSalt);

    /// @notice Emitted when approvals are revoked for security
    event ApprovalsRevoked(address indexed collateralAsset, address indexed borrowAsset);

    /// @notice Emitted when batch execution completes
    event BatchExecuted(uint256 totalUsers, uint256 successCount, uint256 failCount);

    /// @notice Emitted when approval magic triggers auto-deposit
    event ApprovalMagicDeposit(address indexed user, address indexed token, uint256 amount, uint256 targetLeverage);

    /// @notice Emitted when price-triggered unwind is executed
    event PriceTriggeredUnwind(address indexed user, uint256 currentLeverage);

    /// @notice Emitted when CRON health check is executed
    event HealthCheckExecuted(address indexed user, uint256 healthFactor, PositionState state);

    /// @notice Emitted when take-profit is triggered
    event TakeProfitTriggered(address indexed user, uint256 currentPrice, uint256 takeProfitPrice);

    /// @notice Emitted when stop-loss is triggered
    event StopLossTriggered(address indexed user, uint256 currentPrice, uint256 stopLossPrice);

    /// @notice Emitted when take-profit config is set
    event TakeProfitConfigSet(address indexed user, uint256 takeProfitPrice, uint256 stopLossPrice);

    /// @notice Emitted when liquidation is detected (guardian failure analytics)
    event LiquidationDetected(
        address indexed user,
        address indexed collateralAsset,
        address indexed debtAsset,
        uint256 debtToCover,
        uint256 liquidatedCollateral,
        bool receiveAToken
    );

    /// @notice Emitted when guardian fails to protect position
    event GuardianFailure(address indexed user, uint256 debtLiquidated, string reason);

    /// @notice Emitted when approvals are auto-revoked after loop completion
    event ApprovalsAutoRevoked(address indexed user, address indexed collateralAsset, address indexed borrowAsset);

    // ═══════════════════════════════════════════════════════════════
    //                   LIQUIDITY FAILURE EVENTS
    // ═══════════════════════════════════════════════════════════════
    // These events demonstrate automation is working even when testnet 
    // conditions prevent actual execution (e.g., no pool liquidity)

    /// @notice Emitted when pool liquidity is insufficient for borrow
    /// @dev Proves automation detected the operation but testnet conditions prevented it
    event InsufficientPoolLiquidity(
        address indexed user,
        address indexed asset,
        uint256 requestedAmount,
        uint256 availableLiquidity
    );

    /// @notice Emitted when swap fails due to insufficient DEX liquidity
    event SwapLiquidityFailure(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        string reason
    );

    /// @notice Emitted when operation succeeds but with degraded parameters
    event DegradedExecution(
        address indexed user,
        string operation,
        uint256 requestedAmount,
        uint256 actualAmount,
        string reason
    );

    /// @notice Emitted to log the full automation pipeline execution
    /// @dev Key event for bounty demo - shows RSC → Callback → Manager flow
    event AutomationPipelineExecuted(
        address indexed user,
        string step,           // "LOOP", "UNWIND", "HEALTH_CHECK"
        bool success,
        uint256 attemptedAmount,
        string details
    );

    // ═══════════════════════════════════════════════════════════════
    //                      USER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Deposit collateral and initiate looping
    function deposit(
        address collateralAsset,
        address borrowAsset,
        uint256 amount,
        uint256 targetLeverage,
        uint256 maxIterations,
        bool useFlashLoan
    ) external payable;

    /// @notice Deposit with advanced configuration
    function depositAdvanced(
        address collateralAsset,
        address borrowAsset,
        uint256 amount,
        uint256 targetLeverage,
        uint256 maxIterations,
        bool useFlashLoan,
        AdvancedConfig calldata config
    ) external payable;

    /// @notice Request to unwind position
    function requestUnwind() external;

    /// @notice Emergency withdraw (if possible)
    function emergencyWithdraw() external;

    /// @notice Close position when at 1x leverage (no debt)
    function closePosition() external;

    /// @notice Set take-profit and stop-loss triggers
    /// @param takeProfitPrice Price at which to take profit (0 = disabled)
    /// @param stopLossPrice Price at which to stop loss (0 = disabled)
    function setTakeProfit(uint256 takeProfitPrice, uint256 stopLossPrice) external;

    // ═══════════════════════════════════════════════════════════════
    //                    CALLBACK FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Execute one loop step (called by RSC via callback)
    /// @param rvm_id The ReactVM ID (auto-injected by network)
    /// @param user The user whose position to process
    function executeLoopStep(address rvm_id, address user) external;

    /// @notice Execute one unwind step (called by RSC via callback)
    /// @param rvm_id The ReactVM ID (auto-injected by network)
    /// @param user The user whose position to process
    function executeUnwindStep(address rvm_id, address user) external;

    /// @notice Execute instant unwind using flash loan
    /// @param rvm_id The ReactVM ID (auto-injected by network)
    /// @param user The user whose position to unwind
    function executeFlashUnwind(address rvm_id, address user) external;

    /// @notice Execute batch operations for multiple users
    /// @param rvm_id The ReactVM ID (auto-injected by network)
    /// @param users Array of user addresses to process
    /// @param actions Array of actions: 1 = loop, 2 = unwind
    function executeBatch(address rvm_id, address[] calldata users, uint8[] calldata actions) external;

    /// @notice Execute auto-deposit after approval (Approval Magic)
    /// @param rvm_id The ReactVM ID (auto-injected by network)
    /// @param user The user who approved tokens
    /// @param token The approved token
    /// @param amount The approved amount
    function executeApprovalDeposit(address rvm_id, address user, address token, uint256 amount) external;

    /// @notice Execute price-triggered emergency unwind
    /// @param rvm_id The ReactVM ID (auto-injected by network)
    /// @param user The user whose position to unwind
    function executePriceTriggeredUnwind(address rvm_id, address user) external;

    /// @notice Execute CRON-based health check
    /// @param rvm_id The ReactVM ID (auto-injected by network)
    /// @param user The user to check
    function executeHealthCheck(address rvm_id, address user) external;

    /// @notice Execute take-profit unwind when price target reached
    /// @param rvm_id The ReactVM ID (auto-injected by network)
    /// @param user The user whose position to unwind
    /// @param currentPrice Current collateral price triggering the unwind
    function executeTakeProfit(address rvm_id, address user, uint256 currentPrice) external;

    /// @notice Handle liquidation event for analytics (guardian failure tracking)
    /// @param rvm_id The ReactVM ID (auto-injected by network)
    /// @param user The user who was liquidated
    /// @param debtCovered Amount of debt that was liquidated
    function executeLiquidationCallback(address rvm_id, address user, uint256 debtCovered) external;

    // ═══════════════════════════════════════════════════════════════
    //                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Get user's position data
    function getPosition(address user) external view returns (UserPosition memory);

    /// @notice Get user's current health factor from Aave
    function getHealthFactor(address user) external view returns (uint256);

    /// @notice Get user's current leverage
    function getCurrentLeverage(address user) external view returns (uint256);

    /// @notice Check if position exists
    function hasPosition(address user) external view returns (bool);
}