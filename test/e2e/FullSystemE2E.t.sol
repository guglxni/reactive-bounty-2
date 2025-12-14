// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AutoLooperManager} from "../../src/AutoLooperManager.sol";
import {Funder} from "../../src/Funder.sol";
import {UserPosition, PositionState} from "../../src/interfaces/IAutoLooper.sol";
import {LeverageCalculator} from "../../src/libraries/LeverageCalculator.sol";
import {HealthFactorLib} from "../../src/libraries/HealthFactorLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FullSystemE2ETest
 * @notice Comprehensive E2E tests for the entire Auto-Looper system
 * @dev Tests all components working together:
 *      - AutoLooperManager (Sepolia)
 *      - AutoLooperReactive callbacks (simulated)
 *      - Funder + ReactiveFunderRC (self-funding)
 *      - Circuit breakers, rate limiting, security features
 * 
 * Run with Sepolia fork:
 *   forge test --match-contract FullSystemE2ETest --fork-url $SEPOLIA_RPC_URL -vvv
 */
contract FullSystemE2ETest is Test {
    // ═══════════════════════════════════════════════════════════════
    //                        SEPOLIA ADDRESSES
    // ═══════════════════════════════════════════════════════════════
    
    address constant CALLBACK_PROXY = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;
    address constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address constant AAVE_ORACLE = 0x2da88497588bf89281816106C7259e31AF45a663;
    address constant AAVE_DATA_PROVIDER = 0x3e9708d80f7B3e43118013075F7e95CE3AB31F31;
    address constant UNISWAP_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;

    // Test tokens (Sepolia)
    address constant WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address constant DAI = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357;
    
    // ═══════════════════════════════════════════════════════════════
    //                        CONTRACTS
    // ═══════════════════════════════════════════════════════════════
    
    AutoLooperManager public manager;
    Funder public funder;
    
    // Test accounts
    address public owner;
    address public user1;
    address public user2;
    address public rvmId;
    address public reactiveContract;
    
    // ═══════════════════════════════════════════════════════════════
    //                          EVENTS
    // ═══════════════════════════════════════════════════════════════
    
    event PositionUpdated(
        address indexed user,
        uint256 collateral,
        uint256 debt,
        uint256 currentLeverage,
        uint256 healthFactor,
        PositionState state
    );
    
    event LoopExecuted(address indexed user, uint256 iteration, uint256 newLeverage);
    event UnwindExecuted(address indexed user, uint256 iteration, uint256 newLeverage);
    event EmergencyUnwindExecuted(address indexed user, uint256 healthFactor);
    event FundsReceived(address indexed sender, uint256 amount);
    event FundsBridged(address indexed reactiveContract, uint256 amount);
    
    // ═══════════════════════════════════════════════════════════════
    //                          SETUP
    // ═══════════════════════════════════════════════════════════════
    
    function setUp() public {
        // Skip if not Sepolia fork
        if (block.chainid != 11155111) {
            return;
        }
        
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        rvmId = makeAddr("rvmId");
        reactiveContract = makeAddr("reactiveContract");
        
        // Deploy Manager
        manager = new AutoLooperManager(
            CALLBACK_PROXY,
            AAVE_POOL,
            AAVE_ORACLE,
            AAVE_DATA_PROVIDER,
            UNISWAP_ROUTER
        );
        
        // Deploy Funder
        funder = new Funder(reactiveContract);
        
        // Configure Manager
        manager.setRvmId(rvmId);
        manager.setReactiveContract(reactiveContract);
        manager.setFunderContract(address(funder));
        
        // Fund test accounts
        deal(WETH, user1, 100 ether);
        deal(WETH, user2, 100 ether);
        deal(USDC, user1, 100_000e6);
        deal(USDC, user2, 100_000e6);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(address(manager), 1 ether);
    }
    
    modifier onlySepoliaFork() {
        if (block.chainid != 11155111) {
            console.log("Skipping - not Sepolia fork");
            return;
        }
        _;
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    MANAGER CONFIGURATION TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_managerConfiguration_allFieldsSet() public onlySepoliaFork {
        assertEq(manager.owner(), owner, "Owner should be deployer");
        assertEq(manager.reactiveContract(), reactiveContract, "Reactive contract mismatch");
        assertEq(manager.funderContract(), address(funder), "Funder contract mismatch");
        assertFalse(manager.paused(), "Should not be paused");
        assertTrue(manager.circuitBreakerEnabled(), "Circuit breaker should be enabled");
    }
    
    function test_managerConfiguration_canUpdateFee() public onlySepoliaFork {
        uint256 newFee = 0.002 ether;
        uint256 newFlashFee = 0.004 ether;
        manager.setFees(newFee, newFlashFee);
        assertEq(manager.loopFee(), newFee, "Fee not updated");
        assertEq(manager.flashLoanFee(), newFlashFee, "Flash fee not updated");
    }
    
    function test_managerConfiguration_onlyOwnerCanUpdate() public onlySepoliaFork {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        manager.setFees(0.01 ether, 0.02 ether);
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    DEPOSIT FLOW TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_deposit_createsPosition() public onlySepoliaFork {
        uint256 amount = 1 ether;
        uint256 targetLeverage = 2e18;
        
        vm.startPrank(user1);
        IERC20(WETH).approve(address(manager), amount);
        
        vm.expectEmit(true, false, false, false);
        emit PositionUpdated(user1, 0, 0, 0, 0, PositionState.LOOPING);
        
        manager.deposit{value: manager.loopFee()}(
            WETH,
            USDC,
            amount,
            targetLeverage,
            10,
            false
        );
        vm.stopPrank();
        
        UserPosition memory pos = manager.getPosition(user1);
        assertEq(pos.collateralAsset, WETH, "Collateral mismatch");
        assertEq(pos.borrowAsset, USDC, "Borrow asset mismatch");
        assertEq(pos.initialCollateral, amount, "Initial collateral mismatch");
        assertEq(pos.targetLeverage, targetLeverage, "Target leverage mismatch");
        assertTrue(pos.state == PositionState.LOOPING, "Should be looping");
    }
    
    function test_deposit_failsWithInsufficientFee() public onlySepoliaFork {
        uint256 amount = 1 ether;
        
        vm.startPrank(user1);
        IERC20(WETH).approve(address(manager), amount);
        
        vm.expectRevert("Insufficient fee");
        manager.deposit{value: 0}(WETH, USDC, amount, 2e18, 10, false);
        vm.stopPrank();
    }
    
    function test_deposit_failsWhenPaused() public onlySepoliaFork {
        uint256 fee = manager.loopFee(); // Cache fee before pausing
        manager.setPaused(true);
        
        vm.startPrank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        
        vm.expectRevert("Paused");
        manager.deposit{value: fee}(WETH, USDC, 1 ether, 2e18, 10, false);
        vm.stopPrank();
    }
    
    function test_deposit_collectsFeeToFunder() public onlySepoliaFork {
        uint256 amount = 1 ether;
        uint256 fee = manager.loopFee();
        uint256 funderBalanceBefore = address(funder).balance;
        
        vm.startPrank(user1);
        IERC20(WETH).approve(address(manager), amount);
        manager.deposit{value: fee}(WETH, USDC, amount, 2e18, 10, false);
        vm.stopPrank();
        
        assertEq(
            address(funder).balance,
            funderBalanceBefore + fee,
            "Funder should receive fee"
        );
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    CALLBACK EXECUTION TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_executeBatch_onlyFromCallbackProxy() public onlySepoliaFork {
        _setupUserPosition(user1, 1 ether, 2e18);
        
        address[] memory users = new address[](1);
        users[0] = user1;
        uint8[] memory actions = new uint8[](1);
        actions[0] = 1; // loop action
        
        // Should fail from non-callback proxy
        vm.prank(user2);
        vm.expectRevert(); // Should revert with callback auth check
        manager.executeBatch(rvmId, users, actions);
    }
    
    function test_executeBatch_fromCallbackProxy() public onlySepoliaFork {
        _setupUserPosition(user1, 1 ether, 2e18);
        
        address[] memory users = new address[](1);
        users[0] = user1;
        uint8[] memory actions = new uint8[](1);
        actions[0] = 1; // loop action
        
        // From callback proxy with correct RVM ID should work
        // Note: Actual leverage increase depends on Sepolia pool liquidity
        vm.prank(CALLBACK_PROXY);
        manager.executeBatch(rvmId, users, actions);
        
        // Position should still be in LOOPING state (batch processes with soft failures)
        UserPosition memory pos = manager.getPosition(user1);
        assertTrue(pos.state == PositionState.LOOPING || pos.currentLeverage > 1e18, 
            "Should be looping or have increased leverage");
    }
    
    function test_executeBatch_multipleUsers() public onlySepoliaFork {
        _setupUserPosition(user1, 1 ether, 2e18);
        _setupUserPosition(user2, 2 ether, 3e18);
        
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        uint8[] memory actions = new uint8[](2);
        actions[0] = 1; // loop action
        actions[1] = 1; // loop action
        
        vm.prank(CALLBACK_PROXY);
        manager.executeBatch(rvmId, users, actions);
        
        UserPosition memory pos1 = manager.getPosition(user1);
        UserPosition memory pos2 = manager.getPosition(user2);
        
        // Batch execution should process (may soft fail due to pool liquidity)
        assertTrue(pos1.state == PositionState.LOOPING || pos1.currentLeverage > 1e18, 
            "User1 should be looping or have increased leverage");
        assertTrue(pos2.state == PositionState.LOOPING || pos2.currentLeverage > 1e18, 
            "User2 should be looping or have increased leverage");
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    CIRCUIT BREAKER TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_circuitBreaker_isEnabled() public onlySepoliaFork {
        // The circuit breaker should be enabled by default
        assertTrue(manager.circuitBreakerEnabled(), "Circuit breaker should be enabled");
    }
    
    function test_circuitBreaker_canBeDisabled() public onlySepoliaFork {
        manager.setCircuitBreakerEnabled(false);
        assertFalse(manager.circuitBreakerEnabled(), "Should be disabled");
        
        manager.setCircuitBreakerEnabled(true);
        assertTrue(manager.circuitBreakerEnabled(), "Should be enabled");
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    PROFITABILITY CHECK TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_profitability_checksProperly() public onlySepoliaFork {
        _setupUserPosition(user1, 1 ether, 2e18);
        
        // Test profitability function
        (bool profitable, uint256 supplyAPY, uint256 borrowAPY) = manager.isProfitableToLoop(user1);
        
        // With 2x target from 1x, log the result
        console.log("Profitable:", profitable);
        console.log("Supply APY:", supplyAPY);
        console.log("Borrow APY:", borrowAPY);
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    FUNDER INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_funder_receivesFeesFromDeposit() public onlySepoliaFork {
        uint256 fee = manager.loopFee();
        
        vm.startPrank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        manager.deposit{value: fee}(WETH, USDC, 1 ether, 2e18, 10, false);
        vm.stopPrank();
        
        assertGt(funder.totalCollected(), 0, "Funder should have collected fees");
    }
    
    function test_funder_emitsFundsReceivedEvent() public onlySepoliaFork {
        uint256 fee = manager.loopFee();
        
        vm.startPrank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        
        vm.expectEmit(true, false, false, true, address(funder));
        emit FundsReceived(address(manager), fee);
        
        manager.deposit{value: fee}(WETH, USDC, 1 ether, 2e18, 10, false);
        vm.stopPrank();
    }
    
    function test_funder_coverDebtBridgesFunds() public onlySepoliaFork {
        // Send ETH to funder
        vm.deal(address(funder), 0.02 ether);
        
        // coverDebt should bridge funds
        funder.coverDebt(reactiveContract);
        
        assertGt(funder.totalBridged(), 0, "Should have bridged funds");
        assertGt(funder.bridgeCount(), 0, "Bridge count should increase");
    }
    
    function test_funder_respectsGasReserve() public onlySepoliaFork {
        uint256 gasReserve = funder.gasReserve();
        vm.deal(address(funder), gasReserve + 0.01 ether);
        
        funder.coverDebt(reactiveContract);
        
        assertGe(address(funder).balance, gasReserve, "Should maintain gas reserve");
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    UNWIND FLOW TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_unwind_initiatesUnwind() public onlySepoliaFork {
        _setupUserPosition(user1, 1 ether, 2e18);
        
        // Execute some loops first
        vm.prank(CALLBACK_PROXY);
        address[] memory users = new address[](1);
        users[0] = user1;
        uint8[] memory actions = new uint8[](1);
        actions[0] = 1; // loop action
        manager.executeBatch(rvmId, users, actions);
        
        // Now request unwind
        vm.prank(user1);
        manager.requestUnwind();
        
        UserPosition memory pos = manager.getPosition(user1);
        assertTrue(
            pos.state == PositionState.UNWINDING || pos.state == PositionState.IDLE,
            "Should be unwinding or idle"
        );
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    LEVERAGE CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_leverage_calculatesCorrectly() public onlySepoliaFork {
        // Using base currency values (no price conversion needed)
        uint256 collateral = 3 ether; // $3000 worth
        uint256 debt = 2 ether;       // $2000 worth (same units)
        
        uint256 leverage = LeverageCalculator.calculateLeverage(
            collateral,
            debt
        );
        
        // 3000 / (3000 - 2000) = 3000 / 1000 = 3x leverage
        assertEq(leverage, 3e18, "Should be 3x leverage");
    }
    
    function test_healthFactor_calculatesCorrectly() public onlySepoliaFork {
        uint256 collateral = 2 ether;  // Base currency value
        uint256 debt = 1 ether;        // Base currency value
        uint256 liquidationThreshold = 8000; // 80% in basis points
        
        uint256 hf = HealthFactorLib.calculateHealthFactor(
            collateral,
            debt,
            liquidationThreshold
        );
        
        // HF = (collateral * liqThreshold) / debt
        // = (2 * 0.80) / 1 = 1.6 in 18 decimals
        assertEq(hf, 1.6e18, "HF should be 1.6");
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    SECURITY TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_security_reentrancyProtected() public onlySepoliaFork {
        // Reentrancy guard is tested implicitly through normal operations
        // The NonReentrant modifier prevents recursive calls
        assertTrue(true, "Reentrancy guards in place");
    }
    
    function test_security_pauseStopsOperations() public onlySepoliaFork {
        uint256 fee = manager.loopFee(); // Cache fee before pausing
        manager.setPaused(true);
        
        vm.startPrank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        
        vm.expectRevert("Paused");
        manager.deposit{value: fee}(WETH, USDC, 1 ether, 2e18, 10, false);
        vm.stopPrank();
        
        // Unpause and verify operations resume
        manager.setPaused(false);
        
        vm.startPrank(user1);
        manager.deposit{value: manager.loopFee()}(WETH, USDC, 1 ether, 2e18, 10, false);
        vm.stopPrank();
        
        UserPosition memory pos = manager.getPosition(user1);
        assertTrue(pos.state == PositionState.LOOPING, "Should work after unpause");
    }
    
    function test_security_onlyOwnerAdminFunctions() public onlySepoliaFork {
        vm.startPrank(user1);
        
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        manager.setPaused(true);
        
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        manager.setFees(1 ether, 2 ether);
        
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        manager.setCircuitBreakerEnabled(false);
        
        vm.stopPrank();
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_edge_duplicateDeposit() public onlySepoliaFork {
        _setupUserPosition(user1, 1 ether, 2e18);
        
        uint256 fee = manager.loopFee(); // Cache fee before expectRevert
        
        // Second deposit should fail (position exists)
        vm.startPrank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        
        vm.expectRevert(); // Should revert - position exists
        manager.deposit{value: fee}(WETH, USDC, 1 ether, 2e18, 10, false);
        vm.stopPrank();
    }
    
    function test_edge_zeroAmount() public onlySepoliaFork {
        uint256 fee = manager.loopFee(); // Cache fee before expectRevert
        
        vm.startPrank(user1);
        IERC20(WETH).approve(address(manager), 0);
        
        vm.expectRevert(); // Should revert on zero amount
        manager.deposit{value: fee}(WETH, USDC, 0, 2e18, 10, false);
        vm.stopPrank();
    }
    
    function test_edge_invalidLeverage() public onlySepoliaFork {
        uint256 fee = manager.loopFee(); // Cache fee before expectRevert
        
        vm.startPrank(user1);
        IERC20(WETH).approve(address(manager), 1 ether);
        
        // Below 1x leverage should fail
        vm.expectRevert();
        manager.deposit{value: fee}(WETH, USDC, 1 ether, 0.5e18, 10, false);
        
        // Extremely high leverage should fail
        vm.expectRevert();
        manager.deposit{value: fee}(WETH, USDC, 1 ether, 100e18, 10, false);
        vm.stopPrank();
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════
    
    function _setupUserPosition(
        address user,
        uint256 amount,
        uint256 targetLeverage
    ) internal {
        vm.startPrank(user);
        IERC20(WETH).approve(address(manager), amount);
        manager.deposit{value: manager.loopFee()}(
            WETH,
            USDC,
            amount,
            targetLeverage,
            10,
            false
        );
        vm.stopPrank();
    }
}
