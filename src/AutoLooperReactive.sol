// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractReactive} from "@reactive/abstract-base/AbstractReactive.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";
import {AbstractPayer} from "@reactive/abstract-base/AbstractPayer.sol";
import {IPayer} from "@reactive/interfaces/IPayer.sol";

/**
 * @title AutoLooperReactive
 * @notice Reactive Smart Contract for automated leverage looping
 * @dev Uses STATELESS design - all decisions based on event data
 * 
 * Architecture:
 * - Monitors PositionUpdated events from AutoLooperManager on Sepolia
 * - Emits callbacks to execute loop/unwind steps based on state
 * - No persistent state stored during react() - all data from events
 * 
 * Key Patterns:
 * - address(0) placeholder for RVM ID injection in callbacks
 * - vmOnly modifier for react() function
 * - rnOnly modifier for admin functions
 * - Subscription in constructor (following working demo patterns)
 */
contract AutoLooperReactive is IReactive, AbstractReactive {
    // ═══════════════════════════════════════════════════════════════
    //                         CONSTANTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice PositionUpdated event topic
    /// @dev keccak256("PositionUpdated(address,uint256,uint256,uint256,uint256,uint8)")
    uint256 private constant POSITION_UPDATED_TOPIC_0 = 
        0xd97440db9c04f33925d0d4f3a9762d3e70c867b5d7e193cb11897e63c88f10de;

    /// @notice Callback gas limit (sufficient for loop/unwind operations)
    uint64 private constant CALLBACK_GAS_LIMIT = 1_000_000;

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

    // ═══════════════════════════════════════════════════════════════
    //                         IMMUTABLES
    // ═══════════════════════════════════════════════════════════════

    /// @notice AutoLooperManager contract address on Sepolia
    address private immutable vault;

    /// @notice Destination chain ID
    uint256 private immutable chainId;

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

    // ═══════════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the reactive contract
     * @param _vault AutoLooperManager address on destination chain
     * @param _chainId Destination chain ID (Sepolia = 11155111)
     */
    constructor(address _vault, uint256 _chainId) payable {
        vault = _vault;
        chainId = _chainId;
        
        // Subscribe to PositionUpdated events in constructor (following official demo pattern)
        // The `if (!vm)` check ensures subscription only happens on Reactive Network,
        // not in ReactVM where the system contract doesn't exist
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

    /**
     * @notice Subscribe to PositionUpdated events from the Manager (backup method)
     * @dev Can be called if constructor subscription needs to be refreshed
     */
    function subscribeToManager() external rnOnly {
        service.subscribe(
            chainId,                     // Chain ID to monitor
            vault,                       // Contract address to monitor
            POSITION_UPDATED_TOPIC_0,    // topic_0 - event signature
            REACTIVE_IGNORE,             // topic_1 - ignore (user address is indexed)
            REACTIVE_IGNORE,             // topic_2 - ignore
            REACTIVE_IGNORE              // topic_3 - ignore
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                      REACT FUNCTION
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice React to PositionUpdated events
     * @dev Called by ReactVM when subscribed events are detected
     *      All decision logic is STATELESS - based solely on event data
     * @param log The log record from the event
     */
    function react(IReactive.LogRecord calldata log) external override vmOnly {
        // Verify this is from our subscribed contract
        if (log._contract != vault) {
            return;
        }

        // Verify correct event topic
        if (log.topic_0 != POSITION_UPDATED_TOPIC_0) {
            return;
        }

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
     * @notice Process position update and emit appropriate callback
     * @param user The user address
     * @param currentLeverage Current leverage (18 decimals)
     * @param targetLeverage Target leverage (18 decimals)
     * @param healthFactor Current health factor (18 decimals)
     * @param iteration Current iteration count
     * @param state Current position state
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
        // STATE_IDLE = do nothing, position is complete
    }

    /**
     * @notice Handle LOOPING state
     */
    function _handleLoopingState(
        address user,
        uint256 currentLeverage,
        uint256 targetLeverage,
        uint256 iteration
    ) internal {
        // Check if target reached
        if (currentLeverage >= targetLeverage) {
            // Target reached, no more callbacks needed
            return;
        }

        // Check iteration limit
        if (iteration >= MAX_ITERATIONS) {
            // Max iterations reached - stop looping
            return;
        }

        // Continue looping - emit callback for next iteration
        _emitLoopCallback(user);
        emit LoopCallbackTriggered(user, currentLeverage, targetLeverage);
    }

    /**
     * @notice Handle UNWINDING state
     */
    function _handleUnwindingState(
        address user,
        uint256 currentLeverage
    ) internal {
        // Check if fully unwound (leverage = 1x)
        if (currentLeverage <= PRECISION) {
            // Fully unwound - do nothing
            return;
        }

        // Continue unwinding
        _emitUnwindCallback(user);
    }

    /**
     * @notice Handle EMERGENCY state
     */
    function _handleEmergencyState(
        address user,
        uint256 currentLeverage
    ) internal {
        // Keep unwinding until safe
        if (currentLeverage <= PRECISION) {
            return; // Done
        }

        _emitUnwindCallback(user);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     CALLBACK EMISSION
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Emit callback to execute next loop step
     * @dev First argument MUST be address(0) - Reactive Network replaces it with RVM ID
     * @param user The user whose position to process
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
     * @dev First argument MUST be address(0) - Reactive Network replaces it with RVM ID
     * @param user The user whose position to unwind
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
    //                     ADMIN FUNCTIONS (RN State)
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Pause the reactive contract by unsubscribing from events
     * @dev Only callable on Reactive Network (not in ReactVM)
     */
    function pause() external rnOnly {
        bytes memory payload = abi.encodeWithSignature(
            "unsubscribe(uint256,address,uint256,uint256,uint256)",
            chainId,
            vault,
            POSITION_UPDATED_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        (bool success,) = address(service).call(payload);
        require(success, "Unsubscribe failed");
    }

    /**
     * @notice Resume the reactive contract by resubscribing to events
     * @dev Only callable on Reactive Network (not in ReactVM)
     */
    function resume() external rnOnly {
        bytes memory payload = abi.encodeWithSignature(
            "subscribe(uint256,address,uint256,uint256,uint256)",
            chainId,
            vault,
            POSITION_UPDATED_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        (bool success,) = address(service).call(payload);
        require(success, "Subscribe failed");
    }

    // ═══════════════════════════════════════════════════════════════
    //                      VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Get the vault (AutoLooperManager) address
     * @return The vault address
     */
    function getVault() external view returns (address) {
        return vault;
    }

    /**
     * @notice Get the destination chain ID
     * @return The chain ID
     */
    function getChainId() external view returns (uint256) {
        return chainId;
    }

    /**
     * @notice Receive ETH for gas payments
     */
    receive() external payable override(AbstractPayer, IPayer) {}
}
