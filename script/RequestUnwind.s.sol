// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AutoLooperManager} from "../src/AutoLooperManager.sol";
import {UserPosition, PositionState} from "../src/interfaces/IAutoLooper.sol";

/**
 * @title RequestUnwind
 * @notice Script to request unwinding of a leverage position
 * 
 * Environment Variables:
 *   AUTO_LOOPER_MANAGER - Deployed manager address
 * 
 * Usage:
 *   source .env
 *   forge script script/RequestUnwind.s.sol:RequestUnwind \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast
 */
contract RequestUnwind is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Load manager address
        address managerAddr = vm.envAddress("AUTO_LOOPER_MANAGER");
        AutoLooperManager manager = AutoLooperManager(payable(managerAddr));
        
        console.log("=== Requesting Position Unwind ===");
        console.log("Manager:", managerAddr);
        console.log("User:", deployer);
        
        // Check current position
        UserPosition memory pos = manager.getPosition(deployer);
        uint256 healthFactor = manager.getHealthFactor(deployer);
        
        console.log("Current Leverage:", pos.currentLeverage);
        console.log("Health Factor:", healthFactor);
        
        if (pos.state == PositionState.IDLE) {
            console.log("Error: No active position to unwind");
            return;
        }
        
        if (pos.state == PositionState.UNWINDING) {
            console.log("Position already unwinding");
            return;
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Request unwind
        manager.requestUnwind();
        
        console.log("Unwind requested!");
        
        vm.stopBroadcast();
        
        console.log("\n=== Unwind Initiated ===");
        console.log("Monitor events for progress...");
    }
}
