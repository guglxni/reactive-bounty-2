// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ReactiveFunderRC} from "../src/ReactiveFunderRC.sol";

/**
 * @title DeployReactiveFunder
 * @notice Deployment script for ReactiveFunderRC on Reactive Network (Lasna)
 * 
 * Prerequisites:
 *   - FUNDER_CONTRACT must be set in .env (deploy Funder.sol first)
 *   - AUTO_LOOPER_REACTIVE must be set in .env (deploy AutoLooperReactive first)
 * 
 * Usage:
 *   source .env
 *   forge script script/DeployReactiveFunder.s.sol:DeployReactiveFunder \
 *     --rpc-url $REACTIVE_RPC_URL \
 *     --broadcast
 */
contract DeployReactiveFunder is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Load contract addresses from environment
        address funderContract = vm.envAddress("FUNDER_CONTRACT");
        address autoLooperReactive = vm.envAddress("AUTO_LOOPER_REACTIVE");

        require(funderContract != address(0), "FUNDER_CONTRACT not set in .env");
        require(autoLooperReactive != address(0), "AUTO_LOOPER_REACTIVE not set in .env");

        console.log("Deploying ReactiveFunderRC...");
        console.log("Deployer:", deployer);
        console.log("Funder Contract (Sepolia):", funderContract);
        console.log("AutoLooperReactive (Reactive):", autoLooperReactive);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy with initial REACT for subscriptions
        ReactiveFunderRC funderRC = new ReactiveFunderRC{value: 0.5 ether}(
            funderContract,
            autoLooperReactive
        );

        console.log("ReactiveFunderRC deployed at:", address(funderRC));

        vm.stopBroadcast();

        // Output for .env update
        console.log("\n=== Update .env ===");
        console.log("REACTIVE_FUNDER_RC=", address(funderRC));
    }
}
