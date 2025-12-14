// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AutoLooperManager} from "../src/AutoLooperManager.sol";
import {UserPosition, PositionState} from "../src/interfaces/IAutoLooper.sol";

/**
 * @title EmergencyUnwind
 * @notice Script for emergency position closure
 * 
 * WARNING: This immediately unwinds the position. Use only in emergencies.
 * 
 * Environment Variables:
 *   AUTO_LOOPER_MANAGER - Deployed manager address
 * 
 * Usage:
 *   source .env
 *   forge script script/EmergencyUnwind.s.sol:EmergencyUnwind \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast
 */
contract EmergencyUnwind is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Load manager address
        address managerAddr = vm.envAddress("AUTO_LOOPER_MANAGER");
        AutoLooperManager manager = AutoLooperManager(payable(managerAddr));
        
        console.log("=== EMERGENCY UNWIND ===");
        console.log("WARNING: This will immediately close your position!");
        console.log("");
        console.log("Manager:", managerAddr);
        console.log("User:", deployer);
        
        // Check current position
        UserPosition memory pos = manager.getPosition(deployer);
        uint256 healthFactor = manager.getHealthFactor(deployer);
        
        console.log("Current Leverage:", pos.currentLeverage);
        console.log("Health Factor:", healthFactor);
        
        if (pos.state == PositionState.IDLE) {
            console.log("Error: No active position");
            return;
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Emergency withdraw
        manager.emergencyWithdraw();
        
        console.log("Emergency unwind triggered!");
        
        vm.stopBroadcast();
        
        console.log("\n=== Emergency Unwind Initiated ===");
        console.log("Position will be closed as quickly as possible.");
        console.log("Monitor events for completion...");
    }
}
