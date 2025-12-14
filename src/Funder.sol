// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPayable} from "@reactive/interfaces/IPayable.sol";

/**
 * @title Funder
 * @notice Collects fees from users and bridges funds to Reactive Network RSCs
 * @dev Part of the Reactivate self-sustaining gas pattern
 * 
 * This contract enables a self-sustaining ecosystem where:
 * 1. Users pay fees when executing loop operations
 * 2. Fees are collected in this contract
 * 3. FundsReceived events trigger ReactiveFunderRC
 * 4. coverDebt() bridges funds to keep RSCs funded on Reactive Network
 * 
 * Bridge Mechanism:
 * - On Sepolia: Callback Proxy at 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA
 * - depositTo(address) function sends ETH and credits RSC balance
 * - This keeps the reactive contracts funded for continuous operation
 */
contract Funder {
    
    // ═══════════════════════════════════════════════════════════════
    //                         CONSTANTS
    // ═══════════════════════════════════════════════════════════════
    
    /// @notice Sepolia Callback Proxy address (System Contract for bridging)
    /// @dev This is the bridge endpoint - sending ETH here with depositTo(rsc) funds the RSC
    address payable public constant CALLBACK_PROXY = payable(0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA);
    
    /// @notice Reactive Network System Contract address
    /// @dev Used for direct deposits on Reactive Network
    address public constant REACTIVE_SYSTEM_CONTRACT = 0x0000000000000000000000000000000000fffFfF;
    
    /// @notice Minimum transfer amount to avoid dust transfers
    uint256 public constant MIN_TRANSFER_AMOUNT = 0.001 ether;
    
    // ═══════════════════════════════════════════════════════════════
    //                           EVENTS
    // ═══════════════════════════════════════════════════════════════
    
    /// @notice Emitted when funds are received, triggers reactive bridge
    /// @param sender The address that sent the funds
    /// @param amount The amount of ETH received
    event FundsReceived(address indexed sender, uint256 amount);
    
    /// @notice Emitted when funds are bridged to an RSC
    /// @param reactiveContract The RSC that received funding
    /// @param amount The amount bridged
    event FundsBridged(address indexed reactiveContract, uint256 amount);
    
    /// @notice Emitted when funds are withdrawn by owner
    event FundsWithdrawn(address indexed to, uint256 amount);
    
    /// @notice Emitted when bridge threshold is updated
    event BridgeThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    
    /// @notice Emitted when target RSC is updated
    event TargetRscUpdated(address indexed oldRsc, address indexed newRsc);
    
    /// @notice Emitted when bridge fails
    event BridgeFailed(address indexed reactiveContract, uint256 amount, string reason);
    
    // ═══════════════════════════════════════════════════════════════
    //                         STATE
    // ═══════════════════════════════════════════════════════════════
    
    address public immutable owner;
    uint256 public totalCollected;
    uint256 public totalBridged;
    uint256 public bridgeCount;
    
    /// @notice Target RSC address to fund (AutoLooperReactive on Reactive Network)
    address public targetRsc;
    
    /// @notice Minimum amount to trigger bridge (gas efficiency)
    uint256 public bridgeThreshold = 0.01 ether;
    
    /// @notice Amount reserved for gas (not bridged)
    uint256 public gasReserve = 0.005 ether;
    
    /// @notice Authorized callers for coverDebt (callback proxy + owner)
    mapping(address => bool) public authorizedCallers;
    
    // ═══════════════════════════════════════════════════════════════
    //                       CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Initialize Funder with target RSC
     * @param _targetRsc The RSC address to fund on Reactive Network
     */
    constructor(address _targetRsc) {
        owner = msg.sender;
        targetRsc = _targetRsc;
        
        // Authorize callback proxy and owner
        authorizedCallers[CALLBACK_PROXY] = true;
        authorizedCallers[msg.sender] = true;
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                        MODIFIERS
    // ═══════════════════════════════════════════════════════════════
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Funder: only owner");
        _;
    }
    
    modifier onlyAuthorized() {
        require(authorizedCallers[msg.sender] || msg.sender == owner, "Funder: not authorized");
        _;
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                      RECEIVE FUNDS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Receives ETH and emits event for reactive contract
     * @dev The FundsReceived event triggers ReactiveFunderRC to call coverDebt
     */
    receive() external payable {
        _receiveFunds();
    }
    
    /**
     * @notice Explicit fund function (alternative to receive)
     */
    function fund() external payable {
        _receiveFunds();
    }
    
    /**
     * @notice Internal function to handle fund reception
     */
    function _receiveFunds() internal {
        require(msg.value > 0, "Funder: no ETH sent");
        
        totalCollected += msg.value;
        
        // Emit event - this is what the reactive contract listens to
        emit FundsReceived(msg.sender, msg.value);
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                       BRIDGE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Bridge funds to target RSC via Callback Proxy depositTo()
     * @dev Called by ReactiveFunderRC callback or manually by owner
     *      Uses the Callback Proxy's depositTo() function which:
     *      1. Accepts ETH
     *      2. Credits the RSC's balance on Reactive Network
     *      3. Settles any outstanding debt
     * @param reactiveContract The RSC address to fund (must match targetRsc or be set by owner)
     */
    function coverDebt(address reactiveContract) external onlyAuthorized {
        // Default to targetRsc if not specified or zero
        address target = reactiveContract == address(0) ? targetRsc : reactiveContract;
        require(target != address(0), "Funder: no target RSC");
        
        // Calculate available amount (balance - gasReserve)
        uint256 balance = address(this).balance;
        require(balance > gasReserve, "Funder: below gas reserve");
        
        uint256 bridgeAmount = balance - gasReserve;
        require(bridgeAmount >= MIN_TRANSFER_AMOUNT, "Funder: amount too small");
        
        // Bridge via Callback Proxy's depositTo function
        // This sends ETH to the Callback Proxy which credits the RSC on Reactive Network
        (bool success, ) = CALLBACK_PROXY.call{value: bridgeAmount}(
            abi.encodeWithSignature("depositTo(address)", target)
        );
        
        if (success) {
            totalBridged += bridgeAmount;
            bridgeCount++;
            emit FundsBridged(target, bridgeAmount);
        } else {
            // Fallback: try direct transfer to Callback Proxy (simpler but less targeted)
            (bool fallbackSuccess, ) = CALLBACK_PROXY.call{value: bridgeAmount}("");
            
            if (fallbackSuccess) {
                totalBridged += bridgeAmount;
                bridgeCount++;
                emit FundsBridged(target, bridgeAmount);
            } else {
                emit BridgeFailed(target, bridgeAmount, "Both depositTo and direct transfer failed");
                revert("Funder: bridge failed");
            }
        }
    }
    
    /**
     * @notice Check if bridge threshold is met
     * @return True if balance >= threshold + gasReserve
     */
    function canBridge() external view returns (bool) {
        return address(this).balance >= bridgeThreshold + gasReserve;
    }
    
    /**
     * @notice Get amount available for bridging
     * @return bridgeable Amount that can be bridged
     */
    function getBridgeableAmount() external view returns (uint256 bridgeable) {
        uint256 balance = address(this).balance;
        if (balance > gasReserve) {
            bridgeable = balance - gasReserve;
        }
    }
    
    /**
     * @notice Legacy function for backward compatibility
     * @param amount Amount that was bridged (for tracking only)
     */
    function markBridged(uint256 amount) external onlyAuthorized {
        // Just emit event for tracking - actual bridging done in coverDebt
        emit FundsBridged(targetRsc, amount);
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                       ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Set target RSC address
     * @param _targetRsc New target RSC address
     */
    function setTargetRsc(address _targetRsc) external onlyOwner {
        require(_targetRsc != address(0), "Funder: zero address");
        address oldRsc = targetRsc;
        targetRsc = _targetRsc;
        emit TargetRscUpdated(oldRsc, _targetRsc);
    }
    
    /**
     * @notice Set minimum threshold for bridge trigger
     * @param newThreshold New minimum amount
     */
    function setBridgeThreshold(uint256 newThreshold) external onlyOwner {
        uint256 oldThreshold = bridgeThreshold;
        bridgeThreshold = newThreshold;
        emit BridgeThresholdUpdated(oldThreshold, newThreshold);
    }
    
    /**
     * @notice Set gas reserve amount
     * @param _gasReserve New gas reserve amount
     */
    function setGasReserve(uint256 _gasReserve) external onlyOwner {
        gasReserve = _gasReserve;
    }
    
    /**
     * @notice Add/remove authorized caller
     * @param caller Address to authorize/deauthorize
     * @param authorized Whether to authorize or remove
     */
    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
    }
    
    /**
     * @notice Emergency withdraw (owner only)
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address payable to, uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Funder: insufficient balance");
        require(to != address(0), "Funder: zero address");
        
        (bool success, ) = to.call{value: amount}("");
        require(success, "Funder: transfer failed");
        emit FundsWithdrawn(to, amount);
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                       VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    /**
     * @notice Get current contract balance
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @notice Get funding statistics
     */
    function getStats() external view returns (
        uint256 _totalCollected,
        uint256 _totalBridged,
        uint256 _currentBalance,
        uint256 _bridgeThreshold,
        uint256 _bridgeCount,
        address _targetRsc
    ) {
        return (
            totalCollected,
            totalBridged,
            address(this).balance,
            bridgeThreshold,
            bridgeCount,
            targetRsc
        );
    }
    
    /**
     * @notice Check RSC debt on Callback Proxy
     * @param rsc RSC address to check
     * @return debt Outstanding debt amount
     */
    function checkRscDebt(address rsc) external view returns (uint256 debt) {
        try IPayable(CALLBACK_PROXY).debt(rsc) returns (uint256 d) {
            debt = d;
        } catch {
            debt = 0;
        }
    }
}
