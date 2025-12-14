// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AutoLooperManager} from "../../src/AutoLooperManager.sol";
import {UserPosition, PositionState, AdvancedConfig} from "../../src/interfaces/IAutoLooper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title EnhancedCallbacksForkTest
 * @notice Fork tests for enhanced callback functions against real Aave V3 on Sepolia
 * @dev Run with: forge test --match-contract EnhancedCallbacksForkTest --fork-url $SEPOLIA_RPC_URL -vvv
 * 
 * These tests verify the enhanced features work with real Aave protocol:
 * - executeApprovalDeposit (Approval Magic)
 * - executePriceTriggeredUnwind (Stop-Loss)
 * - executeHealthCheck (CRON Monitoring)
 */
contract EnhancedCallbacksForkTest is Test {
    // ═══════════════════════════════════════════════════════════════
    //                        CONSTANTS
    // ═══════════════════════════════════════════════════════════════

    uint256 constant PRECISION = 1e18;

    // Sepolia testnet addresses (Aave V3)
    address constant CALLBACK_PROXY = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;
    address constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address constant AAVE_ORACLE = 0x2da88497588bf89281816106C7259e31AF45a663;
    address constant DATA_PROVIDER = 0x3e9708d80f7B3e43118013075F7e95CE3AB31F31;
    address constant SWAP_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    
    // Test tokens (Sepolia)
    address constant WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;

    // ═══════════════════════════════════════════════════════════════
    //                        TEST STATE
    // ═══════════════════════════════════════════════════════════════

    AutoLooperManager public manager;

    address public deployer;
    address public user1;
    address public user2;
    address public attacker;
    address public rvmId;

    // ═══════════════════════════════════════════════════════════════
    //                          SETUP
    // ═══════════════════════════════════════════════════════════════

    function setUp() public {
        // Skip if not on Sepolia fork
        if (block.chainid != 11155111) {
            return;
        }

        // Create test accounts
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        attacker = makeAddr("attacker");
        rvmId = makeAddr("rvmId");

        // Fund accounts with ETH
        vm.deal(deployer, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(attacker, 1 ether);

        // Deploy manager
        vm.startPrank(deployer);
        manager = new AutoLooperManager(
            CALLBACK_PROXY,
            AAVE_POOL,
            AAVE_ORACLE,
            DATA_PROVIDER,
            SWAP_ROUTER
        );

        // Set RVM ID
        manager.setRvmId(rvmId);

        // Fund manager for gas
        (bool success,) = address(manager).call{value: 1 ether}("");
        require(success, "Fund manager failed");
        vm.stopPrank();

        // Mint test tokens to users
        _mintTestTokens(user1);
        _mintTestTokens(user2);
    }

    function _mintTestTokens(address to) internal {
        deal(WETH, to, 10 ether);
        deal(USDC, to, 100_000e6);
    }

    // ═══════════════════════════════════════════════════════════════
    //                          MODIFIER
    // ═══════════════════════════════════════════════════════════════

    modifier onlyFork() {
        if (block.chainid != 11155111) {
            console.log("Skipping - not Sepolia fork");
            return;
        }
        _;
    }

    // ═══════════════════════════════════════════════════════════════
    //           APPROVAL DEPOSIT TESTS (Approval Magic)
    // ═══════════════════════════════════════════════════════════════

    function test_executeApprovalDeposit_onlyCallbackProxy() public onlyFork {
        vm.prank(attacker);
        vm.expectRevert(); // authorizedSenderOnly
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);
    }

    function test_executeApprovalDeposit_requiresCorrectRvmId() public onlyFork {
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(); // rvmIdOnly
        manager.executeApprovalDeposit(attacker, user1, WETH, 1 ether);
    }

    function test_executeApprovalDeposit_failsWithInsufficientAllowance() public onlyFork {
        // User has not approved tokens
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert("Insufficient allowance");
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);
    }

    function test_executeApprovalDeposit_createsPosition() public onlyFork {
        // User approves WETH to manager
        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);

        // Verify no position exists
        UserPosition memory posBefore = manager.getPosition(user1);
        assertEq(uint8(posBefore.state), uint8(PositionState.IDLE), "Should start IDLE");

        // Callback proxy triggers approval deposit
        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);

        // Verify position was created
        UserPosition memory posAfter = manager.getPosition(user1);
        assertEq(uint8(posAfter.state), uint8(PositionState.LOOPING), "Should be LOOPING");
        assertEq(posAfter.collateralAsset, WETH, "Collateral should be WETH");
        assertEq(posAfter.initialCollateral, 1 ether, "Initial collateral should be 1 ETH");
        assertEq(posAfter.targetLeverage, 2e18, "Default leverage should be 2x");
    }

    function test_executeApprovalDeposit_failsWhenPositionExists() public onlyFork {
        // First create a position via approval deposit
        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 2 ether);

        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);

        // Try to create another position - should fail
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert("Position exists");
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);
    }

    function test_executeApprovalDeposit_failsWhenPaused() public onlyFork {
        vm.prank(deployer);
        manager.setPaused(true);

        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);

        vm.prank(CALLBACK_PROXY);
        vm.expectRevert("Paused");
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);
    }

    // ═══════════════════════════════════════════════════════════════
    //          PRICE TRIGGERED UNWIND TESTS (Stop-Loss)
    // ═══════════════════════════════════════════════════════════════

    function test_executePriceTriggeredUnwind_onlyCallbackProxy() public onlyFork {
        vm.prank(attacker);
        vm.expectRevert(); // authorizedSenderOnly
        manager.executePriceTriggeredUnwind(rvmId, user1);
    }

    function test_executePriceTriggeredUnwind_requiresCorrectRvmId() public onlyFork {
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(); // rvmIdOnly
        manager.executePriceTriggeredUnwind(attacker, user1);
    }

    function test_executePriceTriggeredUnwind_failsWithNoPosition() public onlyFork {
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert("No active position to unwind");
        manager.executePriceTriggeredUnwind(rvmId, user1);
    }

    function test_executePriceTriggeredUnwind_triggersEmergencyState() public onlyFork {
        // First create a position via approval deposit
        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);

        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);

        // Verify position is LOOPING
        UserPosition memory posBefore = manager.getPosition(user1);
        assertEq(uint8(posBefore.state), uint8(PositionState.LOOPING), "Should be LOOPING");

        // Trigger price-based emergency unwind
        vm.prank(CALLBACK_PROXY);
        manager.executePriceTriggeredUnwind(rvmId, user1);

        // Verify state changed to EMERGENCY
        UserPosition memory posAfter = manager.getPosition(user1);
        assertEq(uint8(posAfter.state), uint8(PositionState.EMERGENCY), "Should be EMERGENCY");
    }

    function test_executePriceTriggeredUnwind_failsWhenPaused() public onlyFork {
        // First create a position
        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);

        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);

        // Pause contract
        vm.prank(deployer);
        manager.setPaused(true);

        // Try to trigger unwind - should fail
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert("Paused");
        manager.executePriceTriggeredUnwind(rvmId, user1);
    }

    // ═══════════════════════════════════════════════════════════════
    //             HEALTH CHECK TESTS (CRON Monitoring)
    // ═══════════════════════════════════════════════════════════════

    function test_executeHealthCheck_onlyCallbackProxy() public onlyFork {
        vm.prank(attacker);
        vm.expectRevert(); // authorizedSenderOnly
        manager.executeHealthCheck(rvmId, user1);
    }

    function test_executeHealthCheck_requiresCorrectRvmId() public onlyFork {
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(); // rvmIdOnly
        manager.executeHealthCheck(attacker, user1);
    }

    function test_executeHealthCheck_skipsIdlePositions() public onlyFork {
        // User has no position - should not revert, just skip
        vm.prank(CALLBACK_PROXY);
        manager.executeHealthCheck(rvmId, user1);
        
        // Verify position is still IDLE (unchanged)
        UserPosition memory pos = manager.getPosition(user1);
        assertEq(uint8(pos.state), uint8(PositionState.IDLE), "Should still be IDLE");
    }

    function test_executeHealthCheck_checksActivePosition() public onlyFork {
        // Create a position
        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);

        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);

        // Health check should not revert for active position
        vm.prank(CALLBACK_PROXY);
        manager.executeHealthCheck(rvmId, user1);

        // Position should still be active (health is fine on new position)
        UserPosition memory pos = manager.getPosition(user1);
        assertTrue(
            uint8(pos.state) == uint8(PositionState.LOOPING) || 
            uint8(pos.state) == uint8(PositionState.EMERGENCY),
            "Should be LOOPING or EMERGENCY"
        );
    }

    function test_executeHealthCheck_failsWhenPaused() public onlyFork {
        vm.prank(deployer);
        manager.setPaused(true);

        vm.prank(CALLBACK_PROXY);
        vm.expectRevert("Paused");
        manager.executeHealthCheck(rvmId, user1);
    }

    // ═══════════════════════════════════════════════════════════════
    //                  MULTI-USER SCENARIOS
    // ═══════════════════════════════════════════════════════════════

    function test_multipleUsers_independentPositions() public onlyFork {
        // User1 creates position via approval magic
        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);

        // User2 creates position via approval magic
        vm.prank(user2);
        IERC20(WETH).approve(address(manager), 0.5 ether);
        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user2, WETH, 0.5 ether);

        // Verify both positions exist independently
        UserPosition memory pos1 = manager.getPosition(user1);
        UserPosition memory pos2 = manager.getPosition(user2);

        assertEq(pos1.initialCollateral, 1 ether, "User1 should have 1 ETH");
        assertEq(pos2.initialCollateral, 0.5 ether, "User2 should have 0.5 ETH");

        // Unwind user1's position - should not affect user2
        vm.prank(CALLBACK_PROXY);
        manager.executePriceTriggeredUnwind(rvmId, user1);

        UserPosition memory pos1After = manager.getPosition(user1);
        UserPosition memory pos2After = manager.getPosition(user2);

        assertEq(uint8(pos1After.state), uint8(PositionState.EMERGENCY), "User1 should be EMERGENCY");
        assertEq(uint8(pos2After.state), uint8(PositionState.LOOPING), "User2 should still be LOOPING");
    }

    // ═══════════════════════════════════════════════════════════════
    //                  TAKE-PROFIT TESTS
    // ═══════════════════════════════════════════════════════════════

    function test_setTakeProfit_setsValues() public onlyFork {
        // Create position first
        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);

        // Set take-profit and stop-loss
        vm.prank(user1);
        manager.setTakeProfit(3000e18, 1500e18); // Take profit at $3000, stop-loss at $1500

        UserPosition memory pos = manager.getPosition(user1);
        assertEq(pos.takeProfitPrice, 3000e18, "Take-profit should be set");
        assertEq(pos.stopLossPrice, 1500e18, "Stop-loss should be set");
    }

    function test_setTakeProfit_requiresPositionExists() public onlyFork {
        vm.prank(user1);
        vm.expectRevert("No position");
        manager.setTakeProfit(3000e18, 1500e18);
    }

    function test_setTakeProfit_validatesTakeProfitAboveStopLoss() public onlyFork {
        // Create position first
        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);

        // Try to set take-profit below stop-loss
        vm.prank(user1);
        vm.expectRevert("Take-profit must exceed stop-loss");
        manager.setTakeProfit(1500e18, 3000e18); // Take profit below stop-loss - should fail
    }

    function test_executeTakeProfit_triggersUnwind() public onlyFork {
        // Create position first
        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);

        // Set take-profit
        vm.prank(user1);
        manager.setTakeProfit(2000e18, 0); // Take profit at $2000, no stop-loss

        // Execute take-profit (price reached target)
        vm.prank(CALLBACK_PROXY);
        manager.executeTakeProfit(rvmId, user1, 2100e18); // Current price $2100 >= target $2000

        UserPosition memory pos = manager.getPosition(user1);
        assertEq(uint8(pos.state), uint8(PositionState.UNWINDING), "Should be UNWINDING after take-profit");
    }

    function test_executeTakeProfit_failsIfPriceBelowTarget() public onlyFork {
        // Create position first
        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);

        // Set take-profit
        vm.prank(user1);
        manager.setTakeProfit(3000e18, 0); // Take profit at $3000

        // Try to execute take-profit with price below target
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert("Price below take-profit");
        manager.executeTakeProfit(rvmId, user1, 2500e18); // Current price $2500 < target $3000
    }

    function test_executeTakeProfit_failsWithoutConfig() public onlyFork {
        // Create position but don't set take-profit
        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);

        // Try to execute take-profit without config
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert("Take-profit not configured");
        manager.executeTakeProfit(rvmId, user1, 3000e18);
    }

    // ═══════════════════════════════════════════════════════════════
    //                  LIQUIDATION CALLBACK TESTS
    // ═══════════════════════════════════════════════════════════════

    function test_executeLiquidationCallback_marksEmergency() public onlyFork {
        // Create position first
        vm.prank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        vm.prank(CALLBACK_PROXY);
        manager.executeApprovalDeposit(rvmId, user1, WETH, 1 ether);

        // Simulate liquidation callback (guardian failure)
        vm.prank(CALLBACK_PROXY);
        manager.executeLiquidationCallback(rvmId, user1, 1000e6); // 1000 USDC debt covered

        UserPosition memory pos = manager.getPosition(user1);
        assertEq(uint8(pos.state), uint8(PositionState.EMERGENCY), "Should be EMERGENCY after liquidation");
    }

    function test_executeLiquidationCallback_onlyCallbackProxy() public onlyFork {
        vm.prank(attacker);
        vm.expectRevert("Authorized sender only");
        manager.executeLiquidationCallback(rvmId, user1, 1000e6);
    }

    function test_executeLiquidationCallback_requiresCorrectRvmId() public onlyFork {
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert("Authorized RVM ID only");
        manager.executeLiquidationCallback(attacker, user1, 1000e6);
    }

    // ═══════════════════════════════════════════════════════════════
    //                        RECEIVE ETH
    // ═══════════════════════════════════════════════════════════════

    receive() external payable {}
}
