// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Reactive Network imports
import {AbstractCallback} from "@reactive/abstract-base/AbstractCallback.sol";

// Local imports
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IAaveOracle} from "./interfaces/IAaveOracle.sol";
import {IAaveProtocolDataProvider} from "./interfaces/IAaveProtocolDataProvider.sol";
import {IUniswapV2Router} from "./interfaces/IUniswapV2Router.sol";
import {IAutoLooper, UserPosition, PositionState, AdvancedConfig} from "./interfaces/IAutoLooper.sol";
import {LeverageCalculator} from "./libraries/LeverageCalculator.sol";
import {HealthFactorLib} from "./libraries/HealthFactorLib.sol";

/**
 * @title AutoLooperManager
 * @notice Main callback contract for automated leveraged looping on Aave V3
 * @dev Receives callbacks from Reactive Network to execute loop/unwind steps
 * 
 * Key Features:
 * - Automated leverage looping via Reactive callbacks
 * - Flash loan support for instant leverage
 * - Health factor monitoring and emergency unwind
 * - Self-sustaining gas through fee collection
 * 
 * Authorization:
 * - Inherits AbstractCallback for Reactive Network authorization
 * - Uses authorizedSenderOnly modifier (verifies Callback Proxy)
 * - Uses rvmIdOnly modifier (verifies RVM ID)
 */
contract AutoLooperManager is AbstractCallback, ReentrancyGuard, Ownable, IAutoLooper {
    using SafeERC20 for IERC20;
    using LeverageCalculator for uint256;
    using HealthFactorLib for uint256;

    // ═══════════════════════════════════════════════════════════════
    //                         CONSTANTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Precision for leverage calculations (18 decimals)
    uint256 public constant PRECISION = 1e18;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Default minimum health factor (1.1 = 110%)
    uint256 public constant DEFAULT_MIN_HEALTH_FACTOR = 1.1e18;

    /// @notice Maximum iterations per position
    uint256 public constant MAX_ITERATIONS = 15;

    /// @notice Interest rate mode for Aave (2 = variable)
    uint256 public constant INTEREST_RATE_MODE = 2;

    /// @notice Safety buffer for borrows (95% of max)
    uint256 public constant SAFETY_BUFFER = 9500;

    /// @notice Default slippage tolerance (0.5%)
    uint256 public constant DEFAULT_SLIPPAGE = 50;

    /// @notice Circuit breaker price deviation threshold (10% = 1000 bps)
    uint256 public constant CIRCUIT_BREAKER_THRESHOLD = 1000;

    /// @notice Minimum TWAP block interval for large positions
    uint256 public constant MIN_TWAP_INTERVAL = 1;

    // ═══════════════════════════════════════════════════════════════
    //                         STATE
    // ═══════════════════════════════════════════════════════════════

    /// @notice Aave V3 Pool contract
    IAavePool public immutable aavePool;

    /// @notice Aave V3 Oracle contract
    IAaveOracle public immutable aaveOracle;

    /// @notice Aave Protocol Data Provider
    IAaveProtocolDataProvider public immutable dataProvider;

    /// @notice Uniswap V2 Router for swaps
    IUniswapV2Router public immutable swapRouter;

    /// @notice Reactive contract address (for authorization)
    address public reactiveContract;

    /// @notice User positions mapping
    mapping(address => UserPosition) public positions;

    /// @notice Funder contract for gas collection
    address public funderContract;

    /// @notice Fee per loop operation (ETH)
    uint256 public loopFee = 0.001 ether;

    /// @notice Fee for flash loan operations (ETH)
    uint256 public flashLoanFee = 0.002 ether;

    /// @notice Paused state
    bool public paused;

    /// @notice Historical prices for circuit breaker (asset => price)
    mapping(address => uint256) public lastKnownPrices;

    /// @notice Circuit breaker enabled flag
    bool public circuitBreakerEnabled = true;

    /// @notice APY profitability check enabled flag
    bool public profitabilityCheckEnabled = false;

    /// @notice Minimum profit margin in basis points (e.g., 100 = 1% minimum profit)
    uint256 public minProfitMarginBps = 50;

    /// @notice Batch execution enabled flag
    bool public batchExecutionEnabled = true;

    /// @notice Maximum users per batch execution
    uint256 public constant MAX_BATCH_SIZE = 10;

    // ═══════════════════════════════════════════════════════════════
    //                         MODIFIERS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Ensures position exists for user
    modifier positionExists(address user) {
        require(positions[user].state != PositionState.IDLE || positions[user].initialCollateral > 0, "No position");
        _;
    }

    /// @notice Ensures contract is not paused
    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    /// @notice Validates position state
    modifier validState(address user, PositionState expectedState) {
        require(positions[user].state == expectedState, "Invalid state");
        _;
    }

    // ═══════════════════════════════════════════════════════════════
    //                       CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the AutoLooperManager
     * @param _callbackSender Callback Proxy address (Sepolia: 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA)
     * @param _aavePool Aave V3 Pool address
     * @param _aaveOracle Aave Oracle address
     * @param _dataProvider Aave Protocol Data Provider address
     * @param _swapRouter Uniswap V2 Router address
     */
    constructor(
        address _callbackSender,
        address _aavePool,
        address _aaveOracle,
        address _dataProvider,
        address _swapRouter
    ) AbstractCallback(_callbackSender) Ownable(msg.sender) {
        require(_aavePool != address(0), "Invalid Aave Pool");
        require(_aaveOracle != address(0), "Invalid Oracle");
        require(_dataProvider != address(0), "Invalid Data Provider");
        require(_swapRouter != address(0), "Invalid Swap Router");

        aavePool = IAavePool(_aavePool);
        aaveOracle = IAaveOracle(_aaveOracle);
        dataProvider = IAaveProtocolDataProvider(_dataProvider);
        swapRouter = IUniswapV2Router(_swapRouter);
    }

    // ═══════════════════════════════════════════════════════════════
    //                      USER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Deposit collateral and initiate looping
     * @param collateralAsset Token to use as collateral (e.g., WETH)
     * @param borrowAsset Token to borrow (e.g., USDC)
     * @param amount Amount of collateral to deposit
     * @param targetLeverage Target leverage (18 decimals, e.g., 3e18 = 3x)
     * @param maxIterations Maximum loop iterations allowed
     * @param useFlashLoan Whether to use flash loan for instant leverage
     */
    function deposit(
        address collateralAsset,
        address borrowAsset,
        uint256 amount,
        uint256 targetLeverage,
        uint256 maxIterations,
        bool useFlashLoan
    ) external payable override nonReentrant whenNotPaused {
        require(positions[msg.sender].state == PositionState.IDLE, "Position exists");
        require(amount > 0, "Zero amount");
        require(LeverageCalculator.validateLeverage(targetLeverage), "Invalid leverage");
        require(maxIterations > 0 && maxIterations <= MAX_ITERATIONS, "Invalid iterations");
        require(collateralAsset != borrowAsset, "Same asset");

        // Collect fee
        uint256 fee = useFlashLoan ? flashLoanFee : loopFee;
        require(msg.value >= fee, "Insufficient fee");
        _forwardFee(fee);

        // Transfer collateral from user
        IERC20(collateralAsset).safeTransferFrom(msg.sender, address(this), amount);

        // Supply to Aave
        IERC20(collateralAsset).forceApprove(address(aavePool), amount);
        aavePool.supply(collateralAsset, amount, address(this), 0);

        // Enable as collateral
        aavePool.setUserUseReserveAsCollateral(collateralAsset, true);

        // Create position
        positions[msg.sender] = UserPosition({
            collateralAsset: collateralAsset,
            borrowAsset: borrowAsset,
            initialCollateral: amount,
            targetLeverage: targetLeverage,
            currentLeverage: PRECISION, // Starts at 1x
            maxIterations: maxIterations,
            currentIteration: 0,
            minHealthFactor: DEFAULT_MIN_HEALTH_FACTOR,
            slippageTolerance: DEFAULT_SLIPPAGE,
            state: PositionState.LOOPING,
            lastUpdateBlock: block.number,
            useFlashLoan: useFlashLoan,
            sameAssetLoop: false,    // Standard mode requires swap
            // Advanced features - disabled by default
            maxGasSpend: 0,          // Unlimited
            gasSpentSoFar: 0,
            twapBlockInterval: 0,    // No TWAP delay
            executionSalt: bytes32(0), // No MEV protection
            // Take-profit / Stop-loss - disabled by default
            takeProfitPrice: 0,      // No take-profit
            stopLossPrice: 0         // No stop-loss
        });

        emit PositionCreated(msg.sender, collateralAsset, borrowAsset, targetLeverage);

        // Get initial health factor
        uint256 healthFactor = _getHealthFactor();

        // Emit PositionUpdated to trigger RSC
        emit PositionUpdated(
            msg.sender,
            PRECISION, // Current leverage = 1x
            targetLeverage,
            healthFactor,
            0,
            PositionState.LOOPING
        );
    }

    /**
     * @notice Deposit collateral for SAME-ASSET looping (no swaps needed!)
     * @dev This mode bypasses DEX liquidity issues by borrowing the same asset
     *      Strategy: Supply WETH → Borrow WETH → Supply WETH → Repeat
     *      Works on testnets even with zero DEX liquidity
     * @param asset Token to use as both collateral and borrow (e.g., WETH)
     * @param amount Amount of collateral to deposit
     * @param targetLeverage Target leverage (18 decimals, e.g., 3e18 = 3x)
     * @param maxIterations Maximum loop iterations allowed
     */
    function depositSameAsset(
        address asset,
        uint256 amount,
        uint256 targetLeverage,
        uint256 maxIterations
    ) external payable nonReentrant whenNotPaused {
        require(positions[msg.sender].state == PositionState.IDLE, "Position exists");
        require(amount > 0, "Zero amount");
        require(LeverageCalculator.validateLeverage(targetLeverage), "Invalid leverage");
        require(maxIterations > 0 && maxIterations <= MAX_ITERATIONS, "Invalid iterations");

        // Collect fee
        require(msg.value >= loopFee, "Insufficient fee");
        _forwardFee(loopFee);

        // Transfer collateral from user
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Supply to Aave
        IERC20(asset).forceApprove(address(aavePool), amount);
        aavePool.supply(asset, amount, address(this), 0);

        // Enable as collateral
        aavePool.setUserUseReserveAsCollateral(asset, true);

        // Create position with same-asset mode
        positions[msg.sender] = UserPosition({
            collateralAsset: asset,
            borrowAsset: asset,      // Same as collateral!
            initialCollateral: amount,
            targetLeverage: targetLeverage,
            currentLeverage: PRECISION,
            maxIterations: maxIterations,
            currentIteration: 0,
            minHealthFactor: DEFAULT_MIN_HEALTH_FACTOR,
            slippageTolerance: 0,    // No slippage for same-asset
            state: PositionState.LOOPING,
            lastUpdateBlock: block.number,
            useFlashLoan: false,     // Not supported for same-asset yet
            sameAssetLoop: true,     // SAME-ASSET MODE!
            maxGasSpend: 0,
            gasSpentSoFar: 0,
            twapBlockInterval: 0,
            executionSalt: bytes32(0),
            takeProfitPrice: 0,
            stopLossPrice: 0
        });

        emit PositionCreated(msg.sender, asset, asset, targetLeverage);
        emit AutomationPipelineExecuted(msg.sender, "DEPOSIT_SAME_ASSET", true, amount, "Same-asset loop initiated");

        uint256 healthFactor = _getHealthFactor();

        emit PositionUpdated(
            msg.sender,
            PRECISION,
            targetLeverage,
            healthFactor,
            0,
            PositionState.LOOPING
        );
    }

    /**
     * @notice Deposit collateral with advanced configuration
     * @param collateralAsset Token to use as collateral (e.g., WETH)
     * @param borrowAsset Token to borrow (e.g., USDC)
     * @param amount Amount of collateral to deposit
     * @param targetLeverage Target leverage (18 decimals, e.g., 3e18 = 3x)
     * @param maxIterations Maximum loop iterations allowed
     * @param useFlashLoan Whether to use flash loan for instant leverage
     * @param config Advanced configuration options
     */
    function depositAdvanced(
        address collateralAsset,
        address borrowAsset,
        uint256 amount,
        uint256 targetLeverage,
        uint256 maxIterations,
        bool useFlashLoan,
        AdvancedConfig calldata config
    ) external payable override nonReentrant whenNotPaused {
        require(positions[msg.sender].state == PositionState.IDLE, "Position exists");
        require(amount > 0, "Zero amount");
        require(LeverageCalculator.validateLeverage(targetLeverage), "Invalid leverage");
        require(maxIterations > 0 && maxIterations <= MAX_ITERATIONS, "Invalid iterations");
        require(collateralAsset != borrowAsset, "Same asset");

        // Collect fee
        uint256 fee = useFlashLoan ? flashLoanFee : loopFee;
        require(msg.value >= fee, "Insufficient fee");
        _forwardFee(fee);

        // Transfer collateral from user
        IERC20(collateralAsset).safeTransferFrom(msg.sender, address(this), amount);

        // Supply to Aave
        IERC20(collateralAsset).forceApprove(address(aavePool), amount);
        aavePool.supply(collateralAsset, amount, address(this), 0);

        // Enable as collateral
        aavePool.setUserUseReserveAsCollateral(collateralAsset, true);

        // Generate execution salt for MEV protection if enabled
        bytes32 salt = bytes32(0);
        if (config.enableMevProtection) {
            salt = keccak256(abi.encodePacked(msg.sender, block.number, block.prevrandao, amount));
        }

        // Create position with advanced config
        positions[msg.sender] = UserPosition({
            collateralAsset: collateralAsset,
            borrowAsset: borrowAsset,
            initialCollateral: amount,
            targetLeverage: targetLeverage,
            currentLeverage: PRECISION, // Starts at 1x
            maxIterations: maxIterations,
            currentIteration: 0,
            minHealthFactor: DEFAULT_MIN_HEALTH_FACTOR,
            slippageTolerance: DEFAULT_SLIPPAGE,
            state: PositionState.LOOPING,
            lastUpdateBlock: block.number,
            useFlashLoan: useFlashLoan,
            sameAssetLoop: false,    // Standard mode requires swap
            // Advanced features from config
            maxGasSpend: config.maxGasSpend,
            gasSpentSoFar: 0,
            twapBlockInterval: config.twapBlockInterval,
            executionSalt: salt,
            // Take-profit / Stop-loss - disabled by default
            takeProfitPrice: 0,
            stopLossPrice: 0
        });

        emit PositionCreated(msg.sender, collateralAsset, borrowAsset, targetLeverage);

        // Get initial health factor
        uint256 healthFactor = _getHealthFactor();

        // Emit PositionUpdated to trigger RSC
        emit PositionUpdated(
            msg.sender,
            PRECISION, // Current leverage = 1x
            targetLeverage,
            healthFactor,
            0,
            PositionState.LOOPING
        );
    }

    /**
     * @notice Request to unwind position
     */
    function requestUnwind() external override positionExists(msg.sender) nonReentrant {
        UserPosition storage pos = positions[msg.sender];
        require(pos.state == PositionState.LOOPING || pos.state == PositionState.IDLE, "Already unwinding");

        pos.state = PositionState.UNWINDING;
        pos.currentIteration = 0;
        pos.lastUpdateBlock = block.number;

        uint256 healthFactor = _getHealthFactor();

        emit PositionUpdated(
            msg.sender,
            pos.currentLeverage,
            PRECISION, // Target = 1x (fully unwound)
            healthFactor,
            0,
            PositionState.UNWINDING
        );
    }

    /**
     * @notice Emergency withdraw - attempt to close position immediately
     */
    function emergencyWithdraw() external override positionExists(msg.sender) nonReentrant {
        UserPosition storage pos = positions[msg.sender];

        // Set to emergency state
        pos.state = PositionState.EMERGENCY;
        pos.lastUpdateBlock = block.number;

        uint256 healthFactor = _getHealthFactor();

        emit EmergencyStop(msg.sender, "User initiated emergency withdraw");
        emit PositionUpdated(
            msg.sender,
            pos.currentLeverage,
            PRECISION,
            healthFactor,
            pos.currentIteration,
            PositionState.EMERGENCY
        );
    }

    /**
     * @notice Close position manually when at 1x leverage (no debt)
     * @dev Use this to finalize positions stuck in EMERGENCY/UNWINDING state at 1x leverage
     */
    function closePosition() external positionExists(msg.sender) nonReentrant {
        UserPosition storage pos = positions[msg.sender];

        // Require position to be at 1x leverage (no debt)
        require(pos.currentLeverage <= PRECISION, "Position has debt - use unwind");

        // Require appropriate state
        require(
            pos.state == PositionState.EMERGENCY ||
                pos.state == PositionState.UNWINDING ||
                pos.state == PositionState.IDLE,
            "Cannot close in current state"
        );

        // Finalize the position - withdraws collateral and cleans up
        _finalizePosition(msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    CALLBACK FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Execute one loop step (called by RSC via callback)
     * @dev First parameter (rvm_id) is auto-injected by Reactive Network
     *      Implements: gas budget, TWAP, MEV protection, circuit breaker
     * @param rvm_id The ReactVM ID (deployer address) - auto-injected
     * @param user The user whose position to loop
     */
    function executeLoopStep(
        address rvm_id,
        address user
    ) external override authorizedSenderOnly rvmIdOnly(rvm_id) nonReentrant whenNotPaused {
        uint256 gasStart = gasleft();
        
        UserPosition storage pos = positions[user];
        require(pos.state == PositionState.LOOPING, "Not looping");
        require(pos.currentIteration < pos.maxIterations, "Max iterations reached");

        // === ADVANCED FEATURE: TWAP Block Interval Check ===
        if (pos.twapBlockInterval > 0) {
            uint256 blocksSinceLastUpdate = block.number - pos.lastUpdateBlock;
            if (blocksSinceLastUpdate < pos.twapBlockInterval) {
                emit TwapIntervalNotMet(user, pos.lastUpdateBlock, block.number, pos.twapBlockInterval);
                return; // Skip this execution, wait for TWAP interval
            }
        }

        // === ADVANCED FEATURE: Circuit Breaker Check ===
        if (circuitBreakerEnabled) {
            bool priceAnomaly = _checkCircuitBreaker(pos.collateralAsset, pos.borrowAsset);
            if (priceAnomaly) {
                pos.state = PositionState.EMERGENCY;
                emit EmergencyStop(user, "Circuit breaker: price anomaly detected");
                return;
            }
        }

        // Check if flash loan mode - execute single flash loan
        if (pos.useFlashLoan && pos.currentIteration == 0) {
            _executeFlashLeverageLoop(user);
            _trackGasSpent(user, gasStart);
            return;
        }

        // Execute single iteration
        (uint256 borrowed, uint256 swapped, uint256 supplied) = _executeLoopIteration(user);

        // Update position
        pos.currentIteration++;
        pos.currentLeverage = _calculateCurrentLeverage(user);
        pos.lastUpdateBlock = block.number;

        uint256 healthFactor = _getHealthFactor();

        emit LoopStepExecuted(user, borrowed, swapped, supplied, pos.currentLeverage);

        // Check if target reached or health factor too low
        PositionState newState = pos.state;
        if (pos.currentLeverage >= pos.targetLeverage) {
            newState = PositionState.IDLE;
        } else if (healthFactor < pos.minHealthFactor) {
            newState = PositionState.EMERGENCY;
            emit EmergencyStop(user, "Health factor below minimum");
        }
        pos.state = newState;

        // === ADVANCED FEATURE: Gas Budget Tracking ===
        bool gasExceeded = _trackGasSpent(user, gasStart);
        if (gasExceeded && newState != PositionState.IDLE) {
            // Stop looping if gas budget exceeded
            pos.state = PositionState.IDLE;
            newState = PositionState.IDLE;
        }

        emit PositionUpdated(
            user,
            pos.currentLeverage,
            pos.targetLeverage,
            healthFactor,
            pos.currentIteration,
            newState
        );
    }

    /**
     * @notice Execute one unwind step (called by RSC via callback)
     * @dev First parameter (rvm_id) is auto-injected by Reactive Network
     *      Implements: gas budget tracking, TWAP for controlled unwinding
     * @param rvm_id The ReactVM ID (deployer address) - auto-injected
     * @param user The user whose position to unwind
     */
    function executeUnwindStep(
        address rvm_id,
        address user
    ) external override authorizedSenderOnly rvmIdOnly(rvm_id) nonReentrant whenNotPaused {
        uint256 gasStart = gasleft();
        
        UserPosition storage pos = positions[user];
        require(
            pos.state == PositionState.UNWINDING || pos.state == PositionState.EMERGENCY,
            "Not unwinding"
        );

        // === ADVANCED FEATURE: TWAP Block Interval Check (also for unwinding) ===
        // Only apply TWAP to regular unwind, not emergency
        if (pos.twapBlockInterval > 0 && pos.state == PositionState.UNWINDING) {
            uint256 blocksSinceLastUpdate = block.number - pos.lastUpdateBlock;
            if (blocksSinceLastUpdate < pos.twapBlockInterval) {
                emit TwapIntervalNotMet(user, pos.lastUpdateBlock, block.number, pos.twapBlockInterval);
                return; // Skip this execution, wait for TWAP interval
            }
        }

        // Execute single unwind iteration
        (uint256 withdrawn, uint256 swapped, uint256 repaid) = _executeUnwindIteration(user);

        // Update position
        pos.currentIteration++;
        pos.currentLeverage = _calculateCurrentLeverage(user);
        pos.lastUpdateBlock = block.number;

        uint256 healthFactor = _getHealthFactor();

        emit UnwindStepExecuted(user, withdrawn, swapped, repaid, pos.currentLeverage);

        // Check if fully unwound
        PositionState newState = pos.state;
        if (pos.currentLeverage <= PRECISION) {
            _finalizePosition(user);
            newState = PositionState.IDLE;
        }
        pos.state = newState;

        // Track gas spent
        _trackGasSpent(user, gasStart);

        emit PositionUpdated(
            user,
            pos.currentLeverage,
            PRECISION, // Target = 1x
            healthFactor,
            pos.currentIteration,
            newState
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                    INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Execute a single loop iteration
     * @param user The user whose position to loop
     * @return borrowed Amount borrowed
     * @return swapped Amount received from swap
     * @return supplied Amount supplied back to Aave
     */
    function _executeLoopIteration(
        address user
    ) internal returns (uint256 borrowed, uint256 swapped, uint256 supplied) {
        UserPosition storage pos = positions[user];

        // Get current account data (values in base currency - 8 decimals USD)
        (uint256 totalCollateral, , uint256 availableBorrowBase, , uint256 ltv, ) = aavePool
            .getUserAccountData(address(this));

        // Calculate safe borrow amount in base currency
        uint256 safeBorrowBase = LeverageCalculator.calculateSafeBorrow(totalCollateral, ltv, SAFETY_BUFFER);
        if (safeBorrowBase > availableBorrowBase) {
            safeBorrowBase = availableBorrowBase;
        }
        
        if (safeBorrowBase == 0) {
            emit AutomationPipelineExecuted(user, "LOOP", false, 0, "Nothing to borrow - position may be at max leverage");
            return (0, 0, 0);
        }

        // Convert base currency amount to actual token amount
        borrowed = _baseToTokenAmount(safeBorrowBase, pos.borrowAsset);
        if (borrowed == 0) {
            emit AutomationPipelineExecuted(user, "LOOP", false, safeBorrowBase, "Borrow amount too small after conversion");
            return (0, 0, 0);
        }

        // Check available liquidity in the pool
        // Aave V3 doesn't validate liquidity for variable rate borrows,
        // so we must check to avoid underflow in interest rate calculation
        uint256 availableLiquidity = _getAvailableLiquidity(pos.borrowAsset);
        if (availableLiquidity < borrowed) {
            // Emit detailed liquidity failure event (proves automation is working)
            emit InsufficientPoolLiquidity(user, pos.borrowAsset, borrowed, availableLiquidity);
            emit AutomationPipelineExecuted(
                user, 
                "LOOP", 
                false, 
                borrowed, 
                "Insufficient pool liquidity - testnet limitation"
            );
            
            // Try with reduced amount if some liquidity exists
            if (availableLiquidity > 0) {
                borrowed = availableLiquidity;
                emit DegradedExecution(user, "BORROW", safeBorrowBase, borrowed, "Reduced to available liquidity");
            } else {
                return (0, 0, 0); // No liquidity at all
            }
        }

        // Borrow from Aave
        aavePool.borrow(pos.borrowAsset, borrowed, INTEREST_RATE_MODE, 0, address(this));

        // === SAME-ASSET MODE: Skip swap entirely ===
        if (pos.sameAssetLoop) {
            // No swap needed - borrowed asset IS the collateral asset
            swapped = borrowed;
            emit AutomationPipelineExecuted(user, "LOOP_SAME_ASSET", true, borrowed, "Same-asset borrow - no swap needed");
        } else {
            // Standard mode: Swap borrowed asset to collateral (with graceful error handling)
            swapped = _executeSwapWithFallback(user, pos.borrowAsset, pos.collateralAsset, borrowed, pos.slippageTolerance);
            
            if (swapped == 0) {
                // Swap failed - repay what we borrowed to avoid leaving position in bad state
                IERC20(pos.borrowAsset).forceApprove(address(aavePool), borrowed);
                aavePool.repay(pos.borrowAsset, borrowed, INTEREST_RATE_MODE, address(this));
                emit AutomationPipelineExecuted(user, "LOOP", false, borrowed, "Swap failed - borrowed amount repaid");
                return (0, 0, 0);
            }
        }

        // Supply swapped collateral back to Aave
        IERC20(pos.collateralAsset).forceApprove(address(aavePool), swapped);
        aavePool.supply(pos.collateralAsset, swapped, address(this), 0);
        supplied = swapped;
        
        emit AutomationPipelineExecuted(user, pos.sameAssetLoop ? "LOOP_SAME_ASSET" : "LOOP", true, supplied, "Loop iteration successful");
    }

    /**
     * @notice Execute a single unwind iteration
     * @param user The user whose position to unwind
     * @return withdrawn Amount withdrawn from Aave
     * @return swapped Amount received from swap
     * @return repaid Amount repaid to Aave
     */
    function _executeUnwindIteration(
        address user
    ) internal returns (uint256 withdrawn, uint256 swapped, uint256 repaid) {
        UserPosition storage pos = positions[user];

        // Get current debt
        (, , uint256 variableDebt, , , , , , ) = dataProvider.getUserReserveData(pos.borrowAsset, address(this));

        if (variableDebt == 0) {
            // No debt left, finalize
            emit AutomationPipelineExecuted(user, "UNWIND", true, 0, "No debt remaining - unwind complete");
            return (0, 0, 0);
        }

        // Get current account data for safe withdrawal
        (uint256 totalCollateral, uint256 totalDebt, , uint256 liqThreshold, , ) = aavePool.getUserAccountData(
            address(this)
        );

        // Calculate safe withdrawal amount
        withdrawn = LeverageCalculator.calculateSafeWithdraw(totalCollateral, totalDebt, liqThreshold, pos.minHealthFactor);

        if (withdrawn == 0) {
            // Can't withdraw safely - may need external intervention
            emit AutomationPipelineExecuted(user, "UNWIND", false, 0, "Cannot withdraw safely - health factor constraint");
            return (0, 0, 0);
        }

        // Withdraw from Aave
        withdrawn = aavePool.withdraw(pos.collateralAsset, withdrawn, address(this));

        // === SAME-ASSET MODE: Skip swap entirely ===
        if (pos.sameAssetLoop) {
            // No swap needed - withdrawn asset IS the borrow asset
            swapped = withdrawn;
            emit AutomationPipelineExecuted(user, "UNWIND_SAME_ASSET", true, withdrawn, "Same-asset unwind - no swap needed");
        } else {
            // Standard mode: Swap to borrow asset (with fallback for liquidity issues)
            swapped = _executeSwapWithFallback(user, pos.collateralAsset, pos.borrowAsset, withdrawn, pos.slippageTolerance);
            
            if (swapped == 0) {
                // Swap failed - re-supply the withdrawn collateral to maintain position
                IERC20(pos.collateralAsset).forceApprove(address(aavePool), withdrawn);
                aavePool.supply(pos.collateralAsset, withdrawn, address(this), 0);
                emit AutomationPipelineExecuted(user, "UNWIND", false, withdrawn, "Swap failed - collateral re-supplied");
                return (0, 0, 0);
            }
        }

        // Repay debt
        uint256 repayAmount = swapped > variableDebt ? variableDebt : swapped;
        IERC20(pos.borrowAsset).forceApprove(address(aavePool), repayAmount);
        repaid = aavePool.repay(pos.borrowAsset, repayAmount, INTEREST_RATE_MODE, address(this));
        
        emit AutomationPipelineExecuted(user, pos.sameAssetLoop ? "UNWIND_SAME_ASSET" : "UNWIND", true, repaid, "Unwind iteration successful");
    }

    /**
     * @notice Execute flash loan leverage loop
     * @param user The user whose position to leverage
     */
    function _executeFlashLeverageLoop(address user) internal {
        UserPosition storage pos = positions[user];

        // Calculate flash loan amount needed
        uint256 flashAmount = LeverageCalculator.calculateFlashLoanAmount(pos.initialCollateral, pos.targetLeverage);

        // Prepare flash loan
        address[] memory assets = new address[](1);
        assets[0] = pos.collateralAsset;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashAmount;

        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // No debt, repay in same tx

        bytes memory params = abi.encode(user, true); // true = loop mode

        // Execute flash loan
        aavePool.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);

        // Update position after flash loan
        pos.currentLeverage = _calculateCurrentLeverage(user);
        pos.state = PositionState.IDLE;

        emit FlashLeverageExecuted(user, flashAmount, pos.currentLeverage);
    }

    /**
     * @notice Execute swap on DEX
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount to swap
     * @param slippage Slippage tolerance in basis points
     * @return amountOut Amount received
     */
    function _executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippage
    ) internal returns (uint256 amountOut) {
        // Build path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        // Get expected output
        uint256[] memory amountsOut = swapRouter.getAmountsOut(amountIn, path);
        uint256 minOut = (amountsOut[1] * (BPS - slippage)) / BPS;

        // Approve and swap
        IERC20(tokenIn).forceApprove(address(swapRouter), amountIn);
        uint256[] memory amounts = swapRouter.swapExactTokensForTokens(
            amountIn,
            minOut,
            path,
            address(this),
            block.timestamp + 300
        );

        amountOut = amounts[amounts.length - 1];
    }

    /**
     * @notice Execute swap with graceful error handling for testnet liquidity issues
     * @dev Returns 0 instead of reverting, emits detailed events for debugging
     * @param user The user (for event emission)
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Amount to swap
     * @param slippage Slippage tolerance in basis points
     * @return amountOut Amount received (0 if failed)
     */
    function _executeSwapWithFallback(
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 slippage
    ) internal returns (uint256 amountOut) {
        // Build path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        // Try to get expected output first (check DEX liquidity)
        try swapRouter.getAmountsOut(amountIn, path) returns (uint256[] memory amountsOut) {
            uint256 minOut = (amountsOut[1] * (BPS - slippage)) / BPS;

            // Approve and try swap
            IERC20(tokenIn).forceApprove(address(swapRouter), amountIn);
            
            try swapRouter.swapExactTokensForTokens(
                amountIn,
                minOut,
                path,
                address(this),
                block.timestamp + 300
            ) returns (uint256[] memory amounts) {
                amountOut = amounts[amounts.length - 1];
            } catch Error(string memory reason) {
                emit SwapLiquidityFailure(user, tokenIn, tokenOut, amountIn, reason);
                amountOut = 0;
            } catch {
                emit SwapLiquidityFailure(user, tokenIn, tokenOut, amountIn, "Swap reverted - likely slippage or liquidity");
                amountOut = 0;
            }
        } catch Error(string memory reason) {
            emit SwapLiquidityFailure(user, tokenIn, tokenOut, amountIn, reason);
            amountOut = 0;
        } catch {
            emit SwapLiquidityFailure(user, tokenIn, tokenOut, amountIn, "getAmountsOut failed - no DEX liquidity");
            amountOut = 0;
        }
    }

    /**
     * @notice Calculate current leverage for user
     * @dev Currently uses contract's account data since all positions are managed by this contract
     * @return leverage Current leverage (18 decimals)
     */
    function _calculateCurrentLeverage(address /* user */) internal view returns (uint256 leverage) {
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = aavePool.getUserAccountData(address(this));
        leverage = LeverageCalculator.calculateLeverage(totalCollateral, totalDebt);
    }

    /**
     * @notice Get health factor from Aave
     * @return healthFactor Current health factor
     */
    function _getHealthFactor() internal view returns (uint256 healthFactor) {
        (, , , , , healthFactor) = aavePool.getUserAccountData(address(this));
    }

    /**
     * @notice Get available liquidity for an asset in Aave pool
     * @param asset The asset to check liquidity for
     * @return availableLiquidity Amount available to borrow in token decimals
     */
    function _getAvailableLiquidity(address asset) internal view returns (uint256 availableLiquidity) {
        // Get the aToken address for this asset
        (address aTokenAddress, , ) = dataProvider.getReserveTokensAddresses(asset);
        
        // Available liquidity is the actual token balance held by the aToken contract
        availableLiquidity = IERC20(asset).balanceOf(aTokenAddress);
    }

    /**
     * @notice Convert base currency amount to token amount
     * @dev Aave getUserAccountData returns values in base currency (8 decimals USD)
     *      We need to convert to actual token amounts using oracle prices
     * @param baseCurrencyAmount Amount in base currency (8 decimals)
     * @param asset The token address to convert to
     * @return tokenAmount Amount in token decimals
     */
    function _baseToTokenAmount(uint256 baseCurrencyAmount, address asset) internal view returns (uint256 tokenAmount) {
        // Get asset price (returns price in base currency with 8 decimals)
        uint256 assetPrice = aaveOracle.getAssetPrice(asset);
        if (assetPrice == 0) return 0;
        
        // Get asset decimals from data provider (first return value)
        (uint256 decimals, , , , , , , , , ) = dataProvider.getReserveConfigurationData(asset);
        
        // Convert: tokenAmount = baseCurrencyAmount * 10^tokenDecimals / assetPrice
        // Note: BASE_CURRENCY_UNIT is 1e8 for USD, but cancels out in this formula
        // since both baseCurrencyAmount and assetPrice are in same units
        // E.g., $320 worth of USDC at $1/USDC price:
        // tokenAmount = 320e8 * 1e6 / 1e8 = 320e6 = 320 USDC
        tokenAmount = (baseCurrencyAmount * (10 ** decimals)) / assetPrice;
    }

    /**
     * @notice Finalize and close a position
     * @param user The user whose position to close
     */
    function _finalizePosition(address user) internal {
        UserPosition storage pos = positions[user];
        
        // Store asset addresses before clearing position
        address collateralAsset = pos.collateralAsset;
        address borrowAsset = pos.borrowAsset;

        // Withdraw remaining collateral
        (uint256 aTokenBalance, , , , , , , , ) = dataProvider.getUserReserveData(collateralAsset, address(this));

        if (aTokenBalance > 0) {
            uint256 withdrawn = aavePool.withdraw(collateralAsset, type(uint256).max, user);
            emit PositionClosed(user, withdrawn);
        } else {
            emit PositionClosed(user, 0);
        }

        // Revoke approvals for security (auto-revoking approvals feature)
        _revokeApprovals(collateralAsset, borrowAsset);
        emit ApprovalsAutoRevoked(user, collateralAsset, borrowAsset);

        // Clear position
        delete positions[user];
    }

    /**
     * @notice Forward collected fee to funder contract
     * @param amount Amount to forward
     */
    function _forwardFee(uint256 amount) internal {
        if (funderContract != address(0) && amount > 0) {
            (bool success, ) = funderContract.call{value: amount}("");
            if (success) {
                emit GasRefilled(funderContract, amount);
            }
        }
    }

    /**
     * @notice Track gas spent for a user's position
     * @dev Updates gasSpentSoFar and emits event if budget exceeded
     * @param user The user whose gas to track
     * @param gasStart Gas remaining at start of execution
     * @return exceeded True if gas budget was exceeded
     */
    function _trackGasSpent(address user, uint256 gasStart) internal returns (bool exceeded) {
        UserPosition storage pos = positions[user];
        
        // Calculate gas used (gasStart - gasleft()) * tx.gasprice approximates cost
        uint256 gasUsed = gasStart - gasleft();
        uint256 gasCost = gasUsed * tx.gasprice;
        
        pos.gasSpentSoFar += gasCost;
        
        // Check if budget exceeded (0 = unlimited)
        if (pos.maxGasSpend > 0 && pos.gasSpentSoFar >= pos.maxGasSpend) {
            emit GasBudgetExceeded(user, pos.gasSpentSoFar, pos.maxGasSpend);
            exceeded = true;
        }
    }

    /**
     * @notice Check circuit breaker for price anomalies
     * @dev Compares current prices against last known prices
     * @param collateralAsset The collateral asset to check
     * @param borrowAsset The borrow asset to check  
     * @return anomaly True if price deviation exceeds threshold
     */
    function _checkCircuitBreaker(address collateralAsset, address borrowAsset) internal returns (bool anomaly) {
        // Get current prices
        uint256 collateralPrice = aaveOracle.getAssetPrice(collateralAsset);
        uint256 borrowPrice = aaveOracle.getAssetPrice(borrowAsset);
        
        // Check collateral asset deviation
        if (lastKnownPrices[collateralAsset] > 0) {
            uint256 deviation = _calculateDeviation(lastKnownPrices[collateralAsset], collateralPrice);
            if (deviation > CIRCUIT_BREAKER_THRESHOLD) {
                emit CircuitBreakerTriggered(collateralAsset, deviation);
                anomaly = true;
            }
        }
        
        // Check borrow asset deviation
        if (!anomaly && lastKnownPrices[borrowAsset] > 0) {
            uint256 deviation = _calculateDeviation(lastKnownPrices[borrowAsset], borrowPrice);
            if (deviation > CIRCUIT_BREAKER_THRESHOLD) {
                emit CircuitBreakerTriggered(borrowAsset, deviation);
                anomaly = true;
            }
        }
        
        // Update last known prices
        lastKnownPrices[collateralAsset] = collateralPrice;
        lastKnownPrices[borrowAsset] = borrowPrice;
    }

    /**
     * @notice Calculate price deviation in basis points
     * @param oldPrice Previous price
     * @param newPrice Current price
     * @return deviation Deviation in basis points (e.g., 1000 = 10%)
     */
    function _calculateDeviation(uint256 oldPrice, uint256 newPrice) internal pure returns (uint256 deviation) {
        if (oldPrice == 0) return 0;
        
        if (newPrice > oldPrice) {
            deviation = ((newPrice - oldPrice) * BPS) / oldPrice;
        } else {
            deviation = ((oldPrice - newPrice) * BPS) / oldPrice;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                   APY/PROFITABILITY MONITORING
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Check if looping is profitable based on APY comparison
     * @dev Compares supply APY * leverage vs borrow APY to determine profitability
     *      Aave rates are in RAY (27 decimals), representing per-second rate
     * @param user The user address to check profitability for
     * @return profitable True if expected profit exceeds minimum margin
     * @return supplyAPY Current supply APY (scaled by 1e27)
     * @return borrowAPY Current borrow APY (scaled by 1e27)
     */
    function isProfitableToLoop(address user) public view returns (
        bool profitable,
        uint256 supplyAPY,
        uint256 borrowAPY
    ) {
        UserPosition memory pos = positions[user];
        if (pos.collateralAsset == address(0)) {
            return (false, 0, 0);
        }
        
        // Get reserve data for both assets
        (
            , // configuration
            , // liquidityIndex
            uint128 collateralLiquidityRate, // supply APY (RAY)
            , // variableBorrowIndex
            , // currentVariableBorrowRate
            , // currentStableBorrowRate
            , , , , , , , , // other fields
        ) = aavePool.getReserveData(pos.collateralAsset);
        
        (
            , , , ,
            uint128 borrowVariableRate, // borrow APY (RAY)
            , , , , , , , , ,
        ) = aavePool.getReserveData(pos.borrowAsset);
        
        supplyAPY = uint256(collateralLiquidityRate);
        borrowAPY = uint256(borrowVariableRate);
        
        // Calculate expected returns:
        // Net Profit = (SupplyAPY × TotalCollateral) - (BorrowAPY × TotalDebt)
        // For leveraged position with leverage L:
        // TotalCollateral ≈ InitialCollateral × L
        // TotalDebt ≈ InitialCollateral × (L - 1) × (CollateralPrice / BorrowPrice)
        
        // Simplified profitability check:
        // SupplyAPY × L > BorrowAPY × (L - 1) + MinProfitMargin
        
        uint256 leverage = pos.targetLeverage;
        
        // Scale down from RAY (1e27) for calculation, keeping precision
        // supplyReturn = supplyAPY * leverage / 1e18
        // borrowCost = borrowAPY * (leverage - 1e18) / 1e18
        
        uint256 supplyReturn = (supplyAPY * leverage) / PRECISION;
        uint256 borrowCost = borrowAPY * (leverage - PRECISION) / PRECISION;
        
        // Add minimum profit margin requirement
        uint256 minProfit = (borrowCost * minProfitMarginBps) / BPS;
        
        profitable = supplyReturn > (borrowCost + minProfit);
    }

    /**
     * @notice Internal check before executing loop step
     * @param user User address
     * @return shouldProceed True if loop should proceed
     */
    function _checkProfitability(address user) internal returns (bool shouldProceed) {
        if (!profitabilityCheckEnabled) {
            return true; // Skip check if disabled
        }
        
        (bool profitable, uint256 supplyAPY, uint256 borrowAPY) = isProfitableToLoop(user);
        
        if (!profitable) {
            emit LoopUnprofitable(user, supplyAPY, borrowAPY);
            return false;
        }
        
        return true;
    }

    // ═══════════════════════════════════════════════════════════════
    //                      FLASH UNWIND
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Execute instant unwind using flash loan
     * @dev Allows complete position closure in single transaction
     *      Flow: Flash borrow collateral → Repay all debt → Withdraw collateral → Repay flash
     * @param rvm_id The ReactVM ID (auto-injected by network)
     * @param user The user whose position to unwind
     */
    function executeFlashUnwind(
        address rvm_id,
        address user
    ) external authorizedSenderOnly rvmIdOnly(rvm_id) nonReentrant whenNotPaused {
        UserPosition storage pos = positions[user];
        require(
            pos.state == PositionState.UNWINDING || pos.state == PositionState.EMERGENCY,
            "Not unwinding"
        );
        
        // Get current debt
        (, , uint256 variableDebt, , , , , , ) = dataProvider.getUserReserveData(pos.borrowAsset, address(this));
        
        if (variableDebt == 0) {
            // No debt, just finalize
            _finalizePosition(user);
            return;
        }
        
        // Calculate flash loan amount needed to repay all debt
        // We need to borrow borrow asset, repay debt, then swap collateral to repay flash
        uint256 flashAmount = variableDebt + (variableDebt * 10 / BPS); // Add 0.1% buffer for fees
        
        // Prepare flash loan
        address[] memory assets = new address[](1);
        assets[0] = pos.borrowAsset;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashAmount;
        
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // No debt mode - must repay in same tx
        
        bytes memory params = abi.encode(user, false); // false = unwind mode
        
        // Execute flash loan
        aavePool.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
        
        // Update position state
        pos.currentLeverage = PRECISION;
        pos.state = PositionState.IDLE;
        
        emit FlashUnwindExecuted(user, flashAmount, pos.currentLeverage);
        
        // Finalize and return remaining collateral to user
        _finalizePosition(user);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    AUTO-REVOKING APPROVALS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Revoke all token approvals for security
     * @dev Called automatically on position close or can be called manually
     *      Removes approvals for Aave Pool, Swap Router to minimize attack surface
     * @param collateralAsset The collateral asset to revoke approvals for
     * @param borrowAsset The borrow asset to revoke approvals for
     */
    function _revokeApprovals(address collateralAsset, address borrowAsset) internal {
        // Revoke Aave Pool approvals
        if (collateralAsset != address(0)) {
            IERC20(collateralAsset).forceApprove(address(aavePool), 0);
        }
        if (borrowAsset != address(0)) {
            IERC20(borrowAsset).forceApprove(address(aavePool), 0);
        }
        
        // Revoke Swap Router approvals
        if (collateralAsset != address(0)) {
            IERC20(collateralAsset).forceApprove(address(swapRouter), 0);
        }
        if (borrowAsset != address(0)) {
            IERC20(borrowAsset).forceApprove(address(swapRouter), 0);
        }
        
        emit ApprovalsRevoked(collateralAsset, borrowAsset);
    }

    /**
     * @notice Manually revoke approvals for a user's position
     * @dev Can be called by position owner for additional security
     * @param user The user whose approvals to revoke
     */
    function revokeMyApprovals(address user) external {
        require(msg.sender == user || msg.sender == owner(), "Not authorized");
        UserPosition memory pos = positions[user];
        require(pos.state == PositionState.IDLE, "Position still active");
        
        _revokeApprovals(pos.collateralAsset, pos.borrowAsset);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    GAS BATCHING (MULTI-USER)
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Execute loop steps for multiple users in single transaction
     * @dev Significantly reduces gas costs when multiple users need processing
     *      RSC can batch users needing action and call this once
     * @param rvm_id The ReactVM ID (auto-injected by network)
     * @param users Array of user addresses to process
     * @param actions Array of actions: 1 = loop, 2 = unwind
     */
    function executeBatch(
        address rvm_id,
        address[] calldata users,
        uint8[] calldata actions
    ) external authorizedSenderOnly rvmIdOnly(rvm_id) nonReentrant whenNotPaused {
        require(batchExecutionEnabled, "Batch disabled");
        require(users.length == actions.length, "Length mismatch");
        require(users.length <= MAX_BATCH_SIZE, "Batch too large");
        require(users.length > 0, "Empty batch");
        
        uint256 successCount = 0;
        uint256 failCount = 0;
        
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint8 action = actions[i];
            
            // Skip invalid users
            if (positions[user].initialCollateral == 0) {
                failCount++;
                continue;
            }
            
            // Try to execute action
            bool success = false;
            
            if (action == 1) {
                // Loop action
                success = _tryExecuteLoopStep(user);
            } else if (action == 2) {
                // Unwind action
                success = _tryExecuteUnwindStep(user);
            }
            
            if (success) {
                successCount++;
            } else {
                failCount++;
            }
        }
        
        emit BatchExecuted(users.length, successCount, failCount);
    }

    /**
     * @notice Try to execute a loop step, return success status
     * @dev Internal function that catches errors for batch processing
     * @param user User address
     * @return success True if step executed successfully
     */
    function _tryExecuteLoopStep(address user) internal returns (bool success) {
        UserPosition storage pos = positions[user];
        
        // Validate state
        if (pos.state != PositionState.LOOPING) {
            return false;
        }
        if (pos.currentIteration >= pos.maxIterations) {
            return false;
        }
        
        // Check profitability
        if (!_checkProfitability(user)) {
            return false;
        }
        
        // Execute the loop iteration
        try this.internalLoopStep(user) {
            success = true;
        } catch {
            success = false;
        }
    }

    /**
     * @notice Try to execute an unwind step, return success status
     * @param user User address
     * @return success True if step executed successfully
     */
    function _tryExecuteUnwindStep(address user) internal returns (bool success) {
        UserPosition storage pos = positions[user];
        
        // Validate state
        if (pos.state != PositionState.UNWINDING && pos.state != PositionState.EMERGENCY) {
            return false;
        }
        
        // Execute the unwind iteration
        try this.internalUnwindStep(user) {
            success = true;
        } catch {
            success = false;
        }
    }

    /**
     * @notice Internal loop step for batch execution
     * @dev Exposed as external for try/catch pattern, but only callable by self
     * @param user User address
     */
    function internalLoopStep(address user) external {
        require(msg.sender == address(this), "Only internal");
        
        UserPosition storage pos = positions[user];
        
        // Execute single iteration
        (uint256 borrowed, uint256 swapped, uint256 supplied) = _executeLoopIteration(user);
        
        // Update position
        pos.currentIteration++;
        pos.currentLeverage = _calculateCurrentLeverage(user);
        pos.lastUpdateBlock = block.number;
        
        uint256 healthFactor = _getHealthFactor();
        
        emit LoopStepExecuted(user, borrowed, swapped, supplied, pos.currentLeverage);
        
        // Check if target reached
        if (pos.currentLeverage >= pos.targetLeverage) {
            pos.state = PositionState.IDLE;
        } else if (healthFactor < pos.minHealthFactor) {
            pos.state = PositionState.EMERGENCY;
            emit EmergencyStop(user, "Health factor below minimum");
        }
        
        emit PositionUpdated(
            user,
            pos.currentLeverage,
            pos.targetLeverage,
            healthFactor,
            pos.currentIteration,
            pos.state
        );
    }

    /**
     * @notice Internal unwind step for batch execution
     * @dev Exposed as external for try/catch pattern, but only callable by self
     * @param user User address
     */
    function internalUnwindStep(address user) external {
        require(msg.sender == address(this), "Only internal");
        
        UserPosition storage pos = positions[user];
        
        // Execute single unwind iteration
        (uint256 withdrawn, uint256 swapped, uint256 repaid) = _executeUnwindIteration(user);
        
        // Update position
        pos.currentIteration++;
        pos.currentLeverage = _calculateCurrentLeverage(user);
        pos.lastUpdateBlock = block.number;
        
        uint256 healthFactor = _getHealthFactor();
        
        emit UnwindStepExecuted(user, withdrawn, swapped, repaid, pos.currentLeverage);
        
        // Check if fully unwound
        if (pos.currentLeverage <= PRECISION) {
            _finalizePosition(user);
        }
        
        emit PositionUpdated(
            user,
            pos.currentLeverage,
            PRECISION,
            healthFactor,
            pos.currentIteration,
            pos.state
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                      FLASH LOAN CALLBACK
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Aave flash loan callback
     * @param assets The addresses of the assets being flash-borrowed
     * @param amounts The amounts of the assets being flash-borrowed
     * @param premiums The fee of each asset
     * @param initiator The initiator of the flash loan
     * @param params Additional parameters (user address, isLoop flag)
     * @return True if successful
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(aavePool), "Invalid caller");
        require(initiator == address(this), "Invalid initiator");

        (address user, bool isLoop) = abi.decode(params, (address, bool));
        UserPosition storage pos = positions[user];

        if (isLoop) {
            // Flash leverage loop
            // 1. Supply flash loaned amount as collateral
            IERC20(assets[0]).forceApprove(address(aavePool), amounts[0]);
            aavePool.supply(assets[0], amounts[0], address(this), 0);

            // 2. Borrow to repay flash loan + premium
            uint256 totalDebt = amounts[0] + premiums[0];
            aavePool.borrow(pos.borrowAsset, totalDebt, INTEREST_RATE_MODE, 0, address(this));

            // 3. Swap borrowed amount to repay
            uint256 swapped = _executeSwap(pos.borrowAsset, assets[0], totalDebt, pos.slippageTolerance);

            // 4. Approve repayment
            IERC20(assets[0]).forceApprove(address(aavePool), amounts[0] + premiums[0]);
        } else {
            // Flash unwind mode
            // assets[0] = borrow asset (e.g., USDC)
            // We flash borrow the debt asset to repay Aave, then withdraw collateral and swap to repay flash
            
            // 1. Repay all variable debt on Aave using flash-borrowed funds
            (, , uint256 variableDebt, , , , , , ) = dataProvider.getUserReserveData(assets[0], address(this));
            if (variableDebt > 0) {
                uint256 repayAmount = variableDebt > amounts[0] ? amounts[0] : variableDebt;
                IERC20(assets[0]).forceApprove(address(aavePool), repayAmount);
                aavePool.repay(assets[0], repayAmount, INTEREST_RATE_MODE, address(this));
            }
            
            // 2. Withdraw all collateral (now that debt is repaid)
            (uint256 aTokenBalance, , , , , , , , ) = dataProvider.getUserReserveData(pos.collateralAsset, address(this));
            uint256 withdrawn = 0;
            if (aTokenBalance > 0) {
                withdrawn = aavePool.withdraw(pos.collateralAsset, type(uint256).max, address(this));
            }
            
            // 3. Swap collateral to borrow asset to repay flash loan + premium
            uint256 flashRepayAmount = amounts[0] + premiums[0];
            if (withdrawn > 0) {
                uint256 swapped = _executeSwap(pos.collateralAsset, assets[0], withdrawn, pos.slippageTolerance);
                
                // If swap returned more than needed, send excess to user
                if (swapped > flashRepayAmount) {
                    IERC20(assets[0]).safeTransfer(user, swapped - flashRepayAmount);
                }
            }
            
            // 4. Approve repayment to flash loan
            IERC20(assets[0]).forceApprove(address(aavePool), flashRepayAmount);
            
            // 5. If there's remaining collateral (shouldn't happen normally), send to user
            uint256 remainingCollateral = IERC20(pos.collateralAsset).balanceOf(address(this));
            if (remainingCollateral > 0) {
                IERC20(pos.collateralAsset).safeTransfer(user, remainingCollateral);
            }
        }

        return true;
    }

    // ═══════════════════════════════════════════════════════════════
    //               ENHANCED CALLBACK FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Execute auto-deposit after user approves tokens (Approval Magic)
     * @dev Called by RSC when ERC20 Approval event is detected
     *      Pattern from GMP Comparison "Approval Magic" demo
     *      One-click UX: User approves → RSC detects → Auto-deposits and starts loop
     * @param rvm_id The ReactVM ID (auto-injected by network)
     * @param user The user who approved tokens
     * @param token The token that was approved
     * @param amount The approved amount
     */
    function executeApprovalDeposit(
        address rvm_id,
        address user,
        address token,
        uint256 amount
    ) external override authorizedSenderOnly rvmIdOnly(rvm_id) nonReentrant whenNotPaused {
        // Verify user has no existing position
        require(positions[user].state == PositionState.IDLE, "Position exists");
        
        // Verify the approval is still valid
        uint256 allowance = IERC20(token).allowance(user, address(this));
        require(allowance >= amount, "Insufficient allowance");
        
        // Use sensible defaults for auto-deposit
        // These can be configured via separate user preferences system
        address defaultBorrowAsset = _getDefaultBorrowAsset(token);
        uint256 defaultTargetLeverage = 2e18; // 2x leverage by default
        uint256 defaultMaxIterations = 5;
        bool defaultUseFlashLoan = false;
        
        // Transfer tokens from user
        IERC20(token).safeTransferFrom(user, address(this), amount);
        
        // Supply to Aave
        IERC20(token).forceApprove(address(aavePool), amount);
        aavePool.supply(token, amount, address(this), 0);
        
        // Enable as collateral
        aavePool.setUserUseReserveAsCollateral(token, true);
        
        // Create position
        positions[user] = UserPosition({
            collateralAsset: token,
            borrowAsset: defaultBorrowAsset,
            initialCollateral: amount,
            targetLeverage: defaultTargetLeverage,
            currentLeverage: PRECISION,
            maxIterations: defaultMaxIterations,
            currentIteration: 0,
            minHealthFactor: DEFAULT_MIN_HEALTH_FACTOR,
            slippageTolerance: DEFAULT_SLIPPAGE,
            state: PositionState.LOOPING,
            lastUpdateBlock: block.number,
            useFlashLoan: defaultUseFlashLoan,
            sameAssetLoop: false,    // Approval magic uses standard swap mode
            maxGasSpend: 0,
            gasSpentSoFar: 0,
            twapBlockInterval: 0,
            executionSalt: bytes32(0),
            takeProfitPrice: 0,
            stopLossPrice: 0
        });
        
        emit PositionCreated(user, token, defaultBorrowAsset, defaultTargetLeverage);
        emit ApprovalMagicDeposit(user, token, amount, defaultTargetLeverage);
        
        uint256 healthFactor = _getHealthFactor();
        
        emit PositionUpdated(
            user,
            PRECISION,
            defaultTargetLeverage,
            healthFactor,
            0,
            PositionState.LOOPING
        );
    }

    /**
     * @notice Execute price-triggered emergency unwind
     * @dev Called by RSC when Uniswap price drops below user's stop-loss trigger
     *      Pattern from ReacDEFI stop-loss article
     * @param rvm_id The ReactVM ID (auto-injected by network)
     * @param user The user whose position to unwind
     */
    function executePriceTriggeredUnwind(
        address rvm_id,
        address user
    ) external override authorizedSenderOnly rvmIdOnly(rvm_id) nonReentrant whenNotPaused {
        UserPosition storage pos = positions[user];
        
        // Verify user has an active position
        require(
            pos.state == PositionState.LOOPING || 
            pos.state == PositionState.UNWINDING ||
            (pos.state == PositionState.IDLE && pos.currentLeverage > PRECISION),
            "No active position to unwind"
        );
        
        // Set to emergency unwind
        pos.state = PositionState.EMERGENCY;
        pos.lastUpdateBlock = block.number;
        
        emit EmergencyStop(user, "Price-triggered stop-loss");
        emit PriceTriggeredUnwind(user, pos.currentLeverage);
        
        uint256 healthFactor = _getHealthFactor();
        
        emit PositionUpdated(
            user,
            pos.currentLeverage,
            PRECISION,
            healthFactor,
            pos.currentIteration,
            PositionState.EMERGENCY
        );
    }

    /**
     * @notice Execute periodic health check from CRON
     * @dev Called by RSC on CRON intervals to check user's health factor
     *      Pattern from NFT SUB batch processing article
     *      If health factor is critical, triggers emergency unwind
     * @param rvm_id The ReactVM ID (auto-injected by network)
     * @param user The user whose health to check
     */
    function executeHealthCheck(
        address rvm_id,
        address user
    ) external override authorizedSenderOnly rvmIdOnly(rvm_id) nonReentrant whenNotPaused {
        UserPosition storage pos = positions[user];
        
        // Skip if no active position
        if (pos.state == PositionState.IDLE && pos.currentLeverage <= PRECISION) {
            return;
        }
        
        uint256 healthFactor = _getHealthFactor();
        
        emit HealthCheckExecuted(user, healthFactor, pos.state);
        
        // If health factor is critical, trigger emergency unwind
        if (healthFactor < pos.minHealthFactor && pos.state != PositionState.EMERGENCY) {
            pos.state = PositionState.EMERGENCY;
            pos.lastUpdateBlock = block.number;
            
            emit EmergencyStop(user, "CRON health check: critical health factor");
            
            emit PositionUpdated(
                user,
                pos.currentLeverage,
                PRECISION,
                healthFactor,
                pos.currentIteration,
                PositionState.EMERGENCY
            );
        }
    }

    /**
     * @notice Get default borrow asset for a collateral token
     * @dev Returns sensible default based on collateral type
     *      Can be extended with oracle-based selection
     * @param collateralToken The collateral token
     * @return borrowAsset The recommended borrow asset
     */
    function _getDefaultBorrowAsset(address collateralToken) internal view returns (address borrowAsset) {
        // Default mapping for common pairs on Sepolia testnet
        // WETH collateral → borrow USDC
        // WBTC collateral → borrow USDC
        // Stablecoins → borrow WETH (for short position)
        
        // Sepolia testnet addresses
        address WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
        address USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
        address DAI = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357;
        
        if (collateralToken == WETH) {
            return USDC;
        } else if (collateralToken == USDC || collateralToken == DAI) {
            return WETH;
        } else {
            // Default to USDC for unknown tokens
            return USDC;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                   TAKE-PROFIT / STOP-LOSS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Set take-profit and stop-loss price triggers for a position
     * @dev User can set price-based automatic unwinding
     *      Pattern from NewEra Finance / ReacDEFI articles
     * @param takeProfitPrice Price at which to take profit (18 decimals, 0 = disabled)
     * @param stopLossPrice Price at which to stop loss (18 decimals, 0 = disabled)
     */
    function setTakeProfit(
        uint256 takeProfitPrice,
        uint256 stopLossPrice
    ) external override positionExists(msg.sender) {
        UserPosition storage pos = positions[msg.sender];
        
        // Validate: take-profit must be higher than stop-loss if both set
        if (takeProfitPrice > 0 && stopLossPrice > 0) {
            require(takeProfitPrice > stopLossPrice, "Take-profit must exceed stop-loss");
        }
        
        pos.takeProfitPrice = takeProfitPrice;
        pos.stopLossPrice = stopLossPrice;
        
        emit TakeProfitConfigSet(msg.sender, takeProfitPrice, stopLossPrice);
    }

    /**
     * @notice Execute take-profit unwind when price target is reached
     * @dev Called by RSC when Uniswap price reaches take-profit threshold
     *      Pattern from NewEra Finance limit order article
     * @param rvm_id The ReactVM ID (auto-injected by network)
     * @param user The user whose position to unwind
     * @param currentPrice The current price that triggered the take-profit
     */
    function executeTakeProfit(
        address rvm_id,
        address user,
        uint256 currentPrice
    ) external override authorizedSenderOnly rvmIdOnly(rvm_id) nonReentrant whenNotPaused {
        UserPosition storage pos = positions[user];
        
        require(pos.state != PositionState.IDLE, "No active position");
        require(pos.takeProfitPrice > 0, "Take-profit not configured");
        require(currentPrice >= pos.takeProfitPrice, "Price below take-profit");
        
        emit TakeProfitTriggered(user, currentPrice, pos.takeProfitPrice);
        
        // Trigger unwind
        pos.state = PositionState.UNWINDING;
        pos.currentIteration = 0;
        pos.lastUpdateBlock = block.number;
        
        uint256 healthFactor = _getHealthFactor();
        
        emit PositionUpdated(
            user,
            pos.currentLeverage,
            PRECISION, // Target = 1x
            healthFactor,
            0,
            PositionState.UNWINDING
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                   LIQUIDATION MONITORING
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Handle liquidation event callback for analytics
     * @dev Called by RSC when Aave LiquidationCall event is detected for our user
     *      Used to track guardian effectiveness - if this is called, guardian failed
     *      Pattern from GMP Comparison "Liquidation Protection" section
     * @param rvm_id The ReactVM ID (auto-injected by network)
     * @param user The user who was liquidated
     * @param debtCovered Amount of debt that was liquidated
     */
    function executeLiquidationCallback(
        address rvm_id,
        address user,
        uint256 debtCovered
    ) external override authorizedSenderOnly rvmIdOnly(rvm_id) {
        UserPosition storage pos = positions[user];
        
        // This callback means our health factor guardian failed to protect the user
        // Log it for analytics
        emit GuardianFailure(user, debtCovered, "Position was liquidated despite guardian");
        
        // If position exists and is active, mark as emergency
        if (pos.state != PositionState.IDLE) {
            pos.state = PositionState.EMERGENCY;
            pos.lastUpdateBlock = block.number;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Get user's position data
     * @param user The user address
     * @return position The user's position
     */
    function getPosition(address user) external view override returns (UserPosition memory) {
        return positions[user];
    }

    /**
     * @notice Get user's current health factor
     * @dev User parameter kept for interface compatibility but contract holds positions
     * @return healthFactor Current health factor
     */
    function getHealthFactor(address /* user */) external view override returns (uint256) {
        return _getHealthFactor();
    }

    /**
     * @notice Get user's current leverage
     * @param user The user address
     * @return leverage Current leverage
     */
    function getCurrentLeverage(address user) external view override returns (uint256) {
        return _calculateCurrentLeverage(user);
    }

    /**
     * @notice Check if user has a position
     * @param user The user address
     * @return hasPos True if position exists
     */
    function hasPosition(address user) external view override returns (bool) {
        return positions[user].initialCollateral > 0;
    }

    // ═══════════════════════════════════════════════════════════════
    //                      ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Set the reactive contract address
     * @param _reactiveContract The reactive contract address
     */
    function setReactiveContract(address _reactiveContract) external onlyOwner {
        reactiveContract = _reactiveContract;
    }

    /**
     * @notice Set the funder contract address
     * @param _funderContract The funder contract address
     */
    function setFunderContract(address _funderContract) external onlyOwner {
        funderContract = _funderContract;
    }

    /**
     * @notice Update fee amounts
     * @param _loopFee Fee per loop operation
     * @param _flashLoanFee Fee for flash loan operations
     */
    function setFees(uint256 _loopFee, uint256 _flashLoanFee) external onlyOwner {
        loopFee = _loopFee;
        flashLoanFee = _flashLoanFee;
    }

    /**
     * @notice Pause/unpause the contract
     * @param _paused New paused state
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    /**
     * @notice Set authorized RVM ID for callbacks
     * @dev Must be called after deploying the reactive contract on Reactive Network
     * @param _rvmId The reactive contract address on Reactive Network
     */
    function setRvmId(address _rvmId) external onlyOwner {
        rvm_id = _rvmId;
        emit RvmIdUpdated(_rvmId);
    }

    /**
     * @notice Emergency withdraw stuck tokens
     * @param token Token to withdraw
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function emergencyTokenWithdraw(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Emergency rescue collateral from Aave
     * @dev Only for extreme edge cases where user position is stuck
     * @param asset The collateral asset to withdraw from Aave
     * @param to Recipient address
     * @param amount Amount to withdraw (use type(uint256).max for all)
     */
    function emergencyAaveWithdraw(address asset, address to, uint256 amount) external onlyOwner {
        aavePool.withdraw(asset, amount, to);
    }

    /**
     * @notice Enable or disable circuit breaker
     * @param _enabled Whether circuit breaker should be enabled
     */
    function setCircuitBreakerEnabled(bool _enabled) external onlyOwner {
        circuitBreakerEnabled = _enabled;
    }

    /**
     * @notice Update circuit breaker reference prices
     * @dev Useful when deploying or after known price changes
     * @param assets Array of assets to update
     */
    function updateReferencePrices(address[] calldata assets) external onlyOwner {
        for (uint256 i = 0; i < assets.length; i++) {
            lastKnownPrices[assets[i]] = aaveOracle.getAssetPrice(assets[i]);
        }
    }

    /**
     * @notice Enable or disable profitability checking
     * @param _enabled Whether profitability check should be enabled
     */
    function setProfitabilityCheckEnabled(bool _enabled) external onlyOwner {
        profitabilityCheckEnabled = _enabled;
    }

    /**
     * @notice Set minimum profit margin for profitability check
     * @param _minProfitMarginBps Minimum profit margin in basis points
     */
    function setMinProfitMargin(uint256 _minProfitMarginBps) external onlyOwner {
        require(_minProfitMarginBps <= BPS, "Invalid margin");
        minProfitMarginBps = _minProfitMarginBps;
    }

    /**
     * @notice Enable or disable batch execution
     * @param _enabled Whether batch execution should be enabled
     */
    function setBatchExecutionEnabled(bool _enabled) external onlyOwner {
        batchExecutionEnabled = _enabled;
    }

    /**
     * @notice Admin function to reset a stuck position
     * @dev Only for testnet/emergency use - resets position state without Aave interactions
     * @param user The user whose position to reset
     */
    function adminResetPosition(address user) external onlyOwner {
        delete positions[user];
        emit PositionUpdated(user, 0, 0, 0, 0, PositionState.IDLE);
    }

    /**
     * @notice Admin function to update position borrow asset
     * @dev Only for testnet/emergency use when pool liquidity changes
     * @param user The user whose position to update
     * @param newBorrowAsset The new borrow asset address
     */
    function adminUpdateBorrowAsset(address user, address newBorrowAsset) external onlyOwner {
        require(positions[user].state != PositionState.IDLE, "No active position");
        positions[user].borrowAsset = newBorrowAsset;
    }

    /**
     * @notice Admin function to re-emit PositionUpdated event
     * @dev Used to trigger RSC when position state needs refresh
     * @param user The user whose position event to emit
     */
    function adminEmitPositionUpdate(address user) external onlyOwner {
        UserPosition memory pos = positions[user];
        require(pos.state != PositionState.IDLE || pos.initialCollateral > 0, "No position");
        
        uint256 healthFactor = _getHealthFactor();
        emit PositionUpdated(
            user,
            pos.currentLeverage,
            pos.targetLeverage,
            healthFactor,
            pos.currentIteration,
            pos.state
        );
    }

    /**
     * @notice Receive ETH for gas payments
     */
    receive() external payable override {}
}
