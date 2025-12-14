// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AutoLooperManager} from "../src/AutoLooperManager.sol";

/**
 * @title DeployManager
 * @notice Deployment script for AutoLooperManager on Sepolia
 * 
 * Usage:
 *   source .env
 *   forge script script/DeployManager.s.sol:DeployManager \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast \
 *     --verify
 */
contract DeployManager is Script {
    // Sepolia Addresses
    address constant CALLBACK_PROXY = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;
    address constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address constant AAVE_ORACLE = 0x2da88497588bf89281816106C7259e31AF45a663;
    address constant AAVE_DATA_PROVIDER = 0x3e9708d80f7B3e43118013075F7e95CE3AB31F31;
    address constant UNISWAP_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying AutoLooperManager...");
        console.log("Deployer:", deployer);
        console.log("Callback Proxy:", CALLBACK_PROXY);
        console.log("Aave Pool:", AAVE_POOL);

        vm.startBroadcast(deployerPrivateKey);

        AutoLooperManager manager = new AutoLooperManager(
            CALLBACK_PROXY,
            AAVE_POOL,
            AAVE_ORACLE,
            AAVE_DATA_PROVIDER,
            UNISWAP_ROUTER
        );

        console.log("AutoLooperManager deployed at:", address(manager));

        vm.stopBroadcast();

        // Output for .env update
        console.log("\n=== Update .env ===");
        console.log("AUTO_LOOPER_MANAGER=", address(manager));
    }
}
