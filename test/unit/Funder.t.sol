// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Funder} from "../../src/Funder.sol";

/**
 * @title FunderTest
 * @notice Unit tests for the Funder contract
 */
contract FunderTest is Test {
    Funder public funder;
    address public owner;
    address public user;
    address payable public recipient;
    address public targetRsc;
    
    event FundsReceived(address indexed sender, uint256 amount);
    event FundsWithdrawn(address indexed to, uint256 amount);
    event BridgeThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event FundsBridged(address indexed reactiveContract, uint256 amount);
    event TargetRscUpdated(address indexed oldRsc, address indexed newRsc);
    
    function setUp() public {
        owner = address(this);
        user = makeAddr("user");
        recipient = payable(makeAddr("recipient"));
        targetRsc = makeAddr("targetRsc");
        
        funder = new Funder(targetRsc);
    }
    
    // Allow receiving ETH in tests
    receive() external payable {}
    
    function test_owner_isDeployer() public view {
        assertEq(funder.owner(), owner, "Owner should be deployer");
    }
    
    function test_targetRsc_isSetInConstructor() public view {
        assertEq(funder.targetRsc(), targetRsc, "Target RSC should be set");
    }
    
    function test_initialBridgeThreshold() public view {
        assertEq(funder.bridgeThreshold(), 0.01 ether, "Default threshold should be 0.01 ETH");
    }
    
    function test_initialGasReserve() public view {
        assertEq(funder.gasReserve(), 0.005 ether, "Default gas reserve should be 0.005 ETH");
    }
    
    function test_fund_emitsEvent() public {
        uint256 amount = 0.1 ether;
        vm.deal(user, 1 ether);
        
        vm.expectEmit(true, false, false, true);
        emit FundsReceived(user, amount);
        
        vm.prank(user);
        funder.fund{value: amount}();
    }
    
    function test_receive_emitsEvent() public {
        uint256 amount = 0.05 ether;
        vm.deal(user, 1 ether);
        
        vm.expectEmit(true, false, false, true);
        emit FundsReceived(user, amount);
        
        vm.prank(user);
        (bool success,) = address(funder).call{value: amount}("");
        assertTrue(success, "Transfer should succeed");
    }
    
    function test_fund_tracksTotalCollected() public {
        vm.deal(user, 1 ether);
        
        vm.prank(user);
        funder.fund{value: 0.1 ether}();
        
        assertEq(funder.totalCollected(), 0.1 ether, "Total collected mismatch");
        
        vm.prank(user);
        funder.fund{value: 0.2 ether}();
        
        assertEq(funder.totalCollected(), 0.3 ether, "Total collected after second fund");
    }
    
    function test_fund_revertsOnZeroAmount() public {
        vm.deal(user, 1 ether);
        
        vm.prank(user);
        vm.expectRevert("Funder: no ETH sent");
        funder.fund{value: 0}();
    }
    
    function test_canBridge_checksThresholdAndReserve() public {
        assertFalse(funder.canBridge(), "Should not be able to bridge with 0 balance");
        
        vm.deal(user, 1 ether);
        vm.prank(user);
        funder.fund{value: 0.005 ether}();  // Below threshold + reserve
        
        assertFalse(funder.canBridge(), "Should not bridge below threshold + reserve");
        
        vm.prank(user);
        funder.fund{value: 0.015 ether}();  // Now at 0.02 ETH (threshold 0.01 + reserve 0.005)
        
        assertTrue(funder.canBridge(), "Should bridge at threshold + reserve");
    }
    
    function test_getBridgeableAmount() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        funder.fund{value: 0.02 ether}();
        
        // Balance = 0.02, reserve = 0.005, bridgeable = 0.015
        uint256 bridgeable = funder.getBridgeableAmount();
        assertEq(bridgeable, 0.015 ether, "Bridgeable amount should be balance - reserve");
    }
    
    function test_setTargetRsc_onlyOwner() public {
        address newRsc = makeAddr("newRsc");
        
        vm.prank(user);
        vm.expectRevert("Funder: only owner");
        funder.setTargetRsc(newRsc);
        
        // Owner can set
        funder.setTargetRsc(newRsc);
        assertEq(funder.targetRsc(), newRsc, "Target RSC should be updated");
    }
    
    function test_setTargetRsc_emitsEvent() public {
        address newRsc = makeAddr("newRsc");
        
        vm.expectEmit(true, true, false, false);
        emit TargetRscUpdated(targetRsc, newRsc);
        
        funder.setTargetRsc(newRsc);
    }
    
    function test_setBridgeThreshold_onlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Funder: only owner");
        funder.setBridgeThreshold(0.02 ether);
        
        // Owner can set
        funder.setBridgeThreshold(0.02 ether);
        assertEq(funder.bridgeThreshold(), 0.02 ether, "Threshold should be updated");
    }
    
    function test_setBridgeThreshold_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit BridgeThresholdUpdated(0.01 ether, 0.05 ether);
        
        funder.setBridgeThreshold(0.05 ether);
    }
    
    function test_setGasReserve_onlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Funder: only owner");
        funder.setGasReserve(0.01 ether);
        
        // Owner can set
        funder.setGasReserve(0.01 ether);
        assertEq(funder.gasReserve(), 0.01 ether, "Gas reserve should be updated");
    }
    
    function test_setAuthorizedCaller_onlyOwner() public {
        address newCaller = makeAddr("caller");
        
        vm.prank(user);
        vm.expectRevert("Funder: only owner");
        funder.setAuthorizedCaller(newCaller, true);
        
        // Owner can set
        funder.setAuthorizedCaller(newCaller, true);
        assertTrue(funder.authorizedCallers(newCaller), "Caller should be authorized");
    }
    
    function test_emergencyWithdraw_onlyOwner() public {
        vm.deal(address(funder), 1 ether);
        
        vm.prank(user);
        vm.expectRevert("Funder: only owner");
        funder.emergencyWithdraw(payable(user), 0.5 ether);
    }
    
    function test_emergencyWithdraw_transfersFunds() public {
        vm.deal(address(funder), 1 ether);
        uint256 balanceBefore = address(owner).balance;
        
        funder.emergencyWithdraw(payable(owner), 0.5 ether);
        
        assertEq(address(owner).balance, balanceBefore + 0.5 ether, "Owner should receive funds");
        assertEq(address(funder).balance, 0.5 ether, "Funder should have remaining");
    }
    
    function test_emergencyWithdraw_revertsInsufficientBalance() public {
        vm.deal(address(funder), 0.1 ether);
        
        vm.expectRevert("Funder: insufficient balance");
        funder.emergencyWithdraw(payable(owner), 0.5 ether);
    }
    
    function test_emergencyWithdraw_revertsZeroAddress() public {
        vm.deal(address(funder), 1 ether);
        
        vm.expectRevert("Funder: zero address");
        funder.emergencyWithdraw(payable(address(0)), 0.5 ether);
    }
    
    function test_getBalance_returnsCorrectBalance() public {
        assertEq(funder.getBalance(), 0, "Initial balance should be 0");
        
        vm.deal(user, 1 ether);
        vm.prank(user);
        funder.fund{value: 0.3 ether}();
        
        assertEq(funder.getBalance(), 0.3 ether, "Balance should be 0.3 ETH");
    }
    
    function test_getStats_returnsAllData() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        funder.fund{value: 0.2 ether}();
        
        (
            uint256 totalCollected,
            uint256 totalBridged,
            uint256 currentBalance,
            uint256 bridgeThreshold,
            uint256 bridgeCount,
            address targetRscReturned
        ) = funder.getStats();
        
        assertEq(totalCollected, 0.2 ether, "Total collected mismatch");
        assertEq(totalBridged, 0, "Total bridged should be 0");
        assertEq(currentBalance, 0.2 ether, "Current balance mismatch");
        assertEq(bridgeThreshold, 0.01 ether, "Bridge threshold mismatch");
        assertEq(bridgeCount, 0, "Bridge count should be 0");
        assertEq(targetRscReturned, targetRsc, "Target RSC mismatch");
    }
    
    function test_markBridged_onlyAuthorized() public {
        vm.prank(user);
        vm.expectRevert("Funder: not authorized");
        funder.markBridged(0.1 ether);
    }
    
    function test_markBridged_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit FundsBridged(targetRsc, 0.1 ether);
        
        funder.markBridged(0.1 ether);
    }
    
    function test_coverDebt_revertsWhenNotAuthorized() public {
        vm.deal(address(funder), 1 ether);
        
        vm.prank(user);
        vm.expectRevert("Funder: not authorized");
        funder.coverDebt(targetRsc);
    }
    
    function test_coverDebt_revertsWhenBelowReserve() public {
        // Fund with just the gas reserve amount
        vm.deal(address(funder), 0.004 ether);
        
        vm.expectRevert("Funder: below gas reserve");
        funder.coverDebt(targetRsc);
    }
    
    function test_coverDebt_revertsWhenAmountTooSmall() public {
        // Fund with just above gas reserve but below min transfer
        vm.deal(address(funder), 0.0055 ether);  // 0.005 reserve + 0.0005 < 0.001 min
        
        vm.expectRevert("Funder: amount too small");
        funder.coverDebt(targetRsc);
    }
}
