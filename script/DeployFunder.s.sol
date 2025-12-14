// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Funder} from "../src/Funder.sol";

/**
 * @title DeployFunder
 * @notice Deployment script for Funder contract on Sepolia
 * 
 * Usage:
 *   source .env
 *   forge script script/DeployFunder.s.sol:DeployFunder \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast \
 *     --verify
 */
contract DeployFunder is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Target RSC address - update after deploying AutoLooperReactive
        address targetRsc = vm.envOr("AUTO_LOOPER_REACTIVE", address(0));

        console.log("Deploying Funder...");
        console.log("Deployer:", deployer);
        console.log("Target RSC:", targetRsc);

        vm.startBroadcast(deployerPrivateKey);

        Funder funder = new Funder(targetRsc);

        console.log("Funder deployed at:", address(funder));

        vm.stopBroadcast();

        // Output for .env update
        console.log("\n=== Update .env ===");
        console.log("FUNDER_CONTRACT=", address(funder));
    }
}
