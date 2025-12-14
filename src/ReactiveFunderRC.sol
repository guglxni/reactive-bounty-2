// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractReactive} from "@reactive/abstract-base/AbstractReactive.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";
import {AbstractPayer} from "@reactive/abstract-base/AbstractPayer.sol";
import {IPayer} from "@reactive/interfaces/IPayer.sol";

/**
 * @title ReactiveFunderRC
 * @notice Reactive contract that monitors Funder and bridges funds to AutoLooperReactive
 * @dev Enables self-sustaining gas for the Auto-Looper system (Reactivate pattern)
 * 
 * Flow:
 * 1. Funder.sol on Sepolia receives fees and emits FundsReceived
 * 2. This contract detects the event and triggers a callback
 * 3. Callback causes funds to be bridged to the reactive contract
 * 4. AutoLooperReactive stays funded for continuous operation
 */
contract ReactiveFunderRC is AbstractReactive {
    // ═══════════════════════════════════════════════════════════════
    //                         CONSTANTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice FundsReceived(address indexed sender, uint256 amount) event topic
    /// @dev keccak256("FundsReceived(address,uint256)")
    uint256 private constant FUNDS_RECEIVED_TOPIC_0 = 
        0x8e47b87b0ef542cdfa1659c551d88bad38aa7f452d2bbb349ab7530dfec8be8f;

    /// @notice Callback gas limit
    uint64 private constant CALLBACK_GAS_LIMIT = 500_000;

    /// @notice Sepolia chain ID
    uint256 private constant SEPOLIA_CHAIN_ID = 11155111;

    /// @notice Reactive Network Lasna chain ID
    uint256 private constant REACTIVE_CHAIN_ID = 5318007;

    /// @notice Minimum amount to trigger bridge (wei)
    uint256 private constant MIN_BRIDGE_AMOUNT = 0.001 ether;

    // ═══════════════════════════════════════════════════════════════
    //                         IMMUTABLES
    // ═══════════════════════════════════════════════════════════════

    /// @notice Funder.sol address on Sepolia
    address private immutable funderContract;

    /// @notice AutoLooperReactive address (recipient of bridged funds)
    address private immutable autoLooperReactive;

    // ═══════════════════════════════════════════════════════════════
    //                           STATE
    // ═══════════════════════════════════════════════════════════════

    /// @notice Total amount bridged (tracked for statistics)
    uint256 public totalBridged;

    /// @notice Number of bridge operations
    uint256 public bridgeCount;

    /// @notice Owner address for admin functions
    address public owner;

    // ═══════════════════════════════════════════════════════════════
    //                           EVENTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Emitted when bridge callback is triggered
    event BridgeTriggered(
        address indexed originalSender,
        uint256 amount,
        uint256 bridgeAmount,
        uint256 timestamp
    );

    /// @notice Emitted when owner is updated
    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);

    // ═══════════════════════════════════════════════════════════════
    //                        CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the reactive funder
     * @param _funderContract Funder.sol address on Sepolia
     * @param _autoLooperReactive AutoLooperReactive address on Reactive Network
     */
    constructor(
        address _funderContract,
        address _autoLooperReactive
    ) payable {
        require(_funderContract != address(0), "Invalid funder");
        require(_autoLooperReactive != address(0), "Invalid recipient");

        funderContract = _funderContract;
        autoLooperReactive = _autoLooperReactive;
        owner = msg.sender;
        
        // Note: Subscription done separately via subscribe() to avoid constructor issues
    }
    
    /**
     * @notice Subscribe to FundsReceived events (call after deployment)
     * @dev Must be called on Reactive Network, not in ReactVM
     */
    function subscribe() external rnOnly {
        service.subscribe(
            SEPOLIA_CHAIN_ID,            // Origin chain
            funderContract,              // Origin contract
            FUNDS_RECEIVED_TOPIC_0,      // Event signature
            REACTIVE_IGNORE,             // Don't filter by sender
            REACTIVE_IGNORE,             // Don't filter by amount
            REACTIVE_IGNORE              // Don't filter by topic_3
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                        MODIFIERS
    // ═══════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // ═══════════════════════════════════════════════════════════════
    //                      REACT FUNCTION
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice React to FundsReceived events by bridging funds
     * @dev Called by ReactVM when subscribed events are detected
     * @param log The log record from the event
     */
    function react(IReactive.LogRecord calldata log) external override vmOnly {
        // Validate origin
        if (log.chain_id != SEPOLIA_CHAIN_ID) {
            return;
        }
        if (log._contract != funderContract) {
            return;
        }
        if (log.topic_0 != FUNDS_RECEIVED_TOPIC_0) {
            return;
        }

        // Extract sender from topic1 (indexed parameter)
        address originalSender = address(uint160(log.topic_1));

        // Decode amount from event data
        uint256 amount = abi.decode(log.data, (uint256));

        // Skip if amount too small (not worth bridging)
        if (amount < MIN_BRIDGE_AMOUNT) {
            return;
        }

        // Calculate bridge amount (95% bridged, 5% kept for gas buffer)
        uint256 bridgeAmount = (amount * 95) / 100;

        // Emit callback to trigger fund transfer
        // The callback doesn't directly transfer - it signals the Funder
        // to release funds through the bridge mechanism
        _emitBridgeCallback(originalSender, bridgeAmount);

        // Track statistics (RN state, not ReactVM state)
        if (!vm) {
            totalBridged += bridgeAmount;
            bridgeCount++;
        }

        emit BridgeTriggered(originalSender, amount, bridgeAmount, block.timestamp);
    }

    /**
     * @notice Emit callback to initiate bridge transfer
     * @dev Calls Funder.coverDebt() which bridges funds via Callback Proxy
     * @param originalSender The original fee payer
     * @param amount Amount to bridge
     */
    function _emitBridgeCallback(address originalSender, uint256 amount) internal {
        // Call coverDebt(address) on Funder - this triggers the actual bridge
        // The Funder.coverDebt() function will:
        // 1. Calculate bridgeable amount (balance - gasReserve)
        // 2. Call CallbackProxy.depositTo(targetRsc) to fund the RSC
        // 3. Track bridged amounts
        bytes memory payload = abi.encodeWithSignature(
            "coverDebt(address)",
            autoLooperReactive  // Target RSC to fund
        );

        emit Callback(
            SEPOLIA_CHAIN_ID,
            funderContract,
            CALLBACK_GAS_LIMIT,
            payload
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //                     ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnerUpdated(oldOwner, newOwner);
    }

    /**
     * @notice Pause the reactive contract
     */
    function pause() external rnOnly {
        bytes memory payload = abi.encodeWithSignature(
            "unsubscribe(uint256,address,uint256,uint256,uint256)",
            SEPOLIA_CHAIN_ID,
            funderContract,
            FUNDS_RECEIVED_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        (bool success,) = address(service).call(payload);
        require(success, "Unsubscribe failed");
    }

    /**
     * @notice Resume the reactive contract
     */
    function resume() external rnOnly {
        bytes memory payload = abi.encodeWithSignature(
            "subscribe(uint256,address,uint256,uint256,uint256)",
            SEPOLIA_CHAIN_ID,
            funderContract,
            FUNDS_RECEIVED_TOPIC_0,
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
     * @notice Get funder contract address
     */
    function getFunderContract() external view returns (address) {
        return funderContract;
    }

    /**
     * @notice Get recipient (AutoLooperReactive) address
     */
    function getRecipient() external view returns (address) {
        return autoLooperReactive;
    }

    /**
     * @notice Get bridge statistics
     */
    function getStats() external view returns (
        uint256 _totalBridged,
        uint256 _bridgeCount,
        address _funder,
        address _recipient
    ) {
        return (totalBridged, bridgeCount, funderContract, autoLooperReactive);
    }

    /**
     * @notice Receive ETH for gas payments
     */
    receive() external payable override(AbstractPayer, IPayer) {}
}
