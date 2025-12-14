// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AutoLooperManager} from "../src/AutoLooperManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title InitiateLoop
 * @notice Script to initiate a leverage loop position
 * 
 * Environment Variables:
 *   AUTO_LOOPER_MANAGER - Deployed manager address
 *   COLLATERAL_TOKEN - Token to use as collateral (default: WETH)
 *   BORROW_TOKEN - Token to borrow (default: USDC)
 *   COLLATERAL_AMOUNT - Amount to deposit (in ether units)
 *   TARGET_LEVERAGE - Target leverage (e.g., 2.5 for 2.5x)
 *   MAX_ITERATIONS - Max loop iterations (default: 10)
 *   USE_FLASH_LOAN - true/false for flash loan mode
 * 
 * Usage:
 *   source .env
 *   forge script script/InitiateLoop.s.sol:InitiateLoop \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast
 */
contract InitiateLoop is Script {
    // Default token addresses (Sepolia)
    address constant WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Load manager address
        address managerAddr = vm.envAddress("AUTO_LOOPER_MANAGER");
        AutoLooperManager manager = AutoLooperManager(payable(managerAddr));
        
        // Load configuration with defaults
        address collateralToken = vm.envOr("COLLATERAL_TOKEN", WETH);
        address borrowToken = vm.envOr("BORROW_TOKEN", USDC);
        uint256 collateralAmount = vm.envOr("COLLATERAL_AMOUNT", uint256(0.1 ether));
        uint256 targetLeverage = vm.envOr("TARGET_LEVERAGE", uint256(2.5e18)); // 2.5x default
        uint256 maxIterations = vm.envOr("MAX_ITERATIONS", uint256(10));
        bool useFlashLoan = vm.envOr("USE_FLASH_LOAN", false);
        
        console.log("=== Initiating Leverage Loop ===");
        console.log("Manager:", managerAddr);
        console.log("Deployer:", deployer);
        console.log("Collateral Token:", collateralToken);
        console.log("Borrow Token:", borrowToken);
        console.log("Collateral Amount:", collateralAmount);
        console.log("Target Leverage:", targetLeverage);
        console.log("Max Iterations:", maxIterations);
        console.log("Use Flash Loan:", useFlashLoan);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Approve collateral token
        IERC20(collateralToken).approve(managerAddr, collateralAmount);
        console.log("Approved collateral transfer");
        
        // Calculate fee
        uint256 fee = useFlashLoan ? manager.flashLoanFee() : manager.loopFee();
        console.log("Fee:", fee);
        
        // Deposit and initiate loop
        manager.deposit{value: fee}(
            collateralToken,
            borrowToken,
            collateralAmount,
            targetLeverage,
            maxIterations,
            useFlashLoan
        );
        
        console.log("Loop initiated!");
        
        vm.stopBroadcast();
        
        console.log("\n=== Position Created ===");
        console.log("Monitor events for progress...");
    }
}
