// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AutoLooperReactive.sol";

contract DeployReactiveScript is Script {
    function run() external {
        // Use REACTIVE_PRIVATE_KEY for Lasna deployment
        uint256 deployerPrivateKey = vm.envUint("REACTIVE_PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        AutoLooperReactive reactive = new AutoLooperReactive{value: 0.1 ether}(
            0xA3Cd95BD9690CE6431c666f454AE858024eFE530,  // NEW Manager on Sepolia (June 2025)
            11155111  // Sepolia chain ID
        );
        
        console.log("AutoLooperReactive deployed to:", address(reactive));
        console.log("IMPORTANT: Call subscribeToManager() manually after deployment");
        
        vm.stopBroadcast();
    }
}

contract SubscribeReactiveScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        address reactiveAddr = vm.envAddress("AUTO_LOOPER_REACTIVE");
        
        vm.startBroadcast(deployerPrivateKey);
        
        AutoLooperReactive reactive = AutoLooperReactive(payable(reactiveAddr));
        reactive.subscribeToManager();
        
        console.log("Subscribed to PositionUpdated events");
        
        vm.stopBroadcast();
    }
}
