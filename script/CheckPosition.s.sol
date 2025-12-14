// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AutoLooperManager} from "../src/AutoLooperManager.sol";
import {UserPosition, PositionState} from "../src/interfaces/IAutoLooper.sol";

/**
 * @title CheckPosition
 * @notice Script to check the status of a user's position
 * 
 * Environment Variables:
 *   AUTO_LOOPER_MANAGER - Deployed manager address
 *   USER_ADDRESS - Address to check (default: deployer)
 * 
 * Usage:
 *   source .env
 *   forge script script/CheckPosition.s.sol:CheckPosition \
 *     --rpc-url $SEPOLIA_RPC_URL
 */
contract CheckPosition is Script {
    function run() external view {
        // Load manager address
        address managerAddr = vm.envAddress("AUTO_LOOPER_MANAGER");
        AutoLooperManager manager = AutoLooperManager(payable(managerAddr));
        
        // Get user address (default to deployer)
        address user = vm.envOr(
            "USER_ADDRESS",
            vm.addr(vm.envUint("SEPOLIA_PRIVATE_KEY"))
        );
        
        console.log("=== Position Status ===");
        console.log("Manager:", managerAddr);
        console.log("User:", user);
        console.log("");
        
        // Get position data
        UserPosition memory pos = manager.getPosition(user);
        
        // State string
        string memory stateStr;
        if (pos.state == PositionState.IDLE) {
            stateStr = "IDLE";
        } else if (pos.state == PositionState.LOOPING) {
            stateStr = "LOOPING";
        } else if (pos.state == PositionState.UNWINDING) {
            stateStr = "UNWINDING";
        } else if (pos.state == PositionState.EMERGENCY) {
            stateStr = "EMERGENCY";
        }
        
        console.log("Collateral Asset:", pos.collateralAsset);
        console.log("Borrow Asset:", pos.borrowAsset);
        console.log("Initial Collateral:", pos.initialCollateral);
        console.log("Current Leverage:", pos.currentLeverage);
        console.log("Target Leverage:", pos.targetLeverage);
        console.log("Current Iteration:", pos.currentIteration);
        console.log("Max Iterations:", pos.maxIterations);
        console.log("Min Health Factor:", pos.minHealthFactor);
        console.log("Slippage Tolerance:", pos.slippageTolerance);
        console.log("State:", stateStr);
        console.log("Use Flash Loan:", pos.useFlashLoan);
        
        // Get health factor from Aave
        uint256 healthFactor = manager.getHealthFactor(user);
        console.log("Health Factor (Aave):", healthFactor);
        
        // Calculate progress
        if (pos.state == PositionState.LOOPING && pos.targetLeverage > 1e18) {
            uint256 progress = ((pos.currentLeverage - 1e18) * 100) / (pos.targetLeverage - 1e18);
            console.log("");
            console.log("Loop Progress:", progress, "%");
        }
        
        // Health status
        console.log("");
        if (healthFactor == 0) {
            console.log("Health Status: No position");
        } else if (healthFactor < 1.1e18) {
            console.log("Health Status: CRITICAL - Below 1.1");
        } else if (healthFactor < 1.3e18) {
            console.log("Health Status: WARNING - Below 1.3");
        } else {
            console.log("Health Status: HEALTHY");
        }
    }
}
