// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Funder} from "../../src/Funder.sol";

/**
 * @title FunderIntegrationTest
 * @notice Local integration tests for the Funder contract (no fork needed)
 * @dev Tests the self-funding (Reactivate) pattern components locally
 */
contract FunderIntegrationTest is Test {
    Funder public funder;
    
    address public owner;
    address public user1;
    address public user2;
    address public targetRsc;
    
    address constant CALLBACK_PROXY = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;
    
    event FundsReceived(address indexed sender, uint256 amount);
    event FundsBridged(address indexed reactiveContract, uint256 amount);
    event FundsWithdrawn(address indexed to, uint256 amount);
    event BridgeThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event TargetRscUpdated(address indexed oldRsc, address indexed newRsc);
    
    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        targetRsc = makeAddr("targetRsc");
        
        funder = new Funder(targetRsc);
        
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    DEPLOYMENT TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_deployment_setsOwner() public view {
        assertEq(funder.owner(), owner);
    }
    
    function test_deployment_setsTargetRsc() public view {
        assertEq(funder.targetRsc(), targetRsc);
    }
    
    function test_deployment_authorizesOwnerAndProxy() public view {
        assertTrue(funder.authorizedCallers(owner));
        assertTrue(funder.authorizedCallers(CALLBACK_PROXY));
    }
    
    function test_deployment_setsDefaultThresholds() public view {
        assertEq(funder.bridgeThreshold(), 0.01 ether);
        assertEq(funder.gasReserve(), 0.005 ether);
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    RECEIVE FUNDS TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_receive_acceptsEth() public {
        uint256 amount = 1 ether;
        
        vm.prank(user1);
        (bool success,) = address(funder).call{value: amount}("");
        
        assertTrue(success, "Transfer should succeed");
        assertEq(address(funder).balance, amount);
    }
    
    function test_receive_updatesTotalCollected() public {
        uint256 amount = 1 ether;
        
        vm.prank(user1);
        (bool success,) = address(funder).call{value: amount}("");
        assertTrue(success);
        
        assertEq(funder.totalCollected(), amount);
    }
    
    function test_receive_emitsFundsReceived() public {
        uint256 amount = 1 ether;
        
        vm.expectEmit(true, false, false, true, address(funder));
        emit FundsReceived(user1, amount);
        
        vm.prank(user1);
        (bool success,) = address(funder).call{value: amount}("");
        assertTrue(success);
    }
    
    function test_receive_revertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("Funder: no ETH sent");
        (bool success,) = address(funder).call{value: 0}("");
        // The call will fail inside receive
        success; // suppress warning
    }
    
    function test_fund_acceptsEth() public {
        uint256 amount = 0.5 ether;
        
        vm.prank(user1);
        funder.fund{value: amount}();
        
        assertEq(address(funder).balance, amount);
        assertEq(funder.totalCollected(), amount);
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    BRIDGING TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_canBridge_returnsFalseWhenBelowThreshold() public {
        vm.deal(address(funder), 0.005 ether); // Below threshold + reserve
        assertFalse(funder.canBridge());
    }
    
    function test_canBridge_returnsTrueWhenAboveThreshold() public {
        vm.deal(address(funder), 0.02 ether); // Above threshold + reserve
        assertTrue(funder.canBridge());
    }
    
    function test_getBridgeableAmount_calculatesCorrectly() public {
        uint256 balance = 0.1 ether;
        uint256 reserve = funder.gasReserve();
        
        vm.deal(address(funder), balance);
        
        assertEq(funder.getBridgeableAmount(), balance - reserve);
    }
    
    function test_getBridgeableAmount_returnsZeroWhenBelowReserve() public {
        vm.deal(address(funder), 0.003 ether); // Below reserve
        assertEq(funder.getBridgeableAmount(), 0);
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    ADMIN TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_setTargetRsc_updatesCorrectly() public {
        address newRsc = makeAddr("newRsc");
        
        vm.expectEmit(true, true, false, false, address(funder));
        emit TargetRscUpdated(targetRsc, newRsc);
        
        funder.setTargetRsc(newRsc);
        
        assertEq(funder.targetRsc(), newRsc);
    }
    
    function test_setTargetRsc_onlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Funder: only owner");
        funder.setTargetRsc(makeAddr("newRsc"));
    }
    
    function test_setTargetRsc_revertsOnZeroAddress() public {
        vm.expectRevert("Funder: zero address");
        funder.setTargetRsc(address(0));
    }
    
    function test_setBridgeThreshold_updatesCorrectly() public {
        uint256 newThreshold = 0.05 ether;
        uint256 oldThreshold = funder.bridgeThreshold();
        
        vm.expectEmit(true, true, false, true, address(funder));
        emit BridgeThresholdUpdated(oldThreshold, newThreshold);
        
        funder.setBridgeThreshold(newThreshold);
        
        assertEq(funder.bridgeThreshold(), newThreshold);
    }
    
    function test_setBridgeThreshold_onlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Funder: only owner");
        funder.setBridgeThreshold(0.05 ether);
    }
    
    function test_setGasReserve_updatesCorrectly() public {
        uint256 newReserve = 0.01 ether;
        funder.setGasReserve(newReserve);
        assertEq(funder.gasReserve(), newReserve);
    }
    
    function test_setGasReserve_onlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Funder: only owner");
        funder.setGasReserve(0.01 ether);
    }
    
    function test_setAuthorizedCaller_addsNewCaller() public {
        address newCaller = makeAddr("newCaller");
        
        assertFalse(funder.authorizedCallers(newCaller));
        
        funder.setAuthorizedCaller(newCaller, true);
        
        assertTrue(funder.authorizedCallers(newCaller));
    }
    
    function test_setAuthorizedCaller_removesCaller() public {
        address caller = makeAddr("caller");
        funder.setAuthorizedCaller(caller, true);
        assertTrue(funder.authorizedCallers(caller));
        
        funder.setAuthorizedCaller(caller, false);
        assertFalse(funder.authorizedCallers(caller));
    }
    
    function test_setAuthorizedCaller_onlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Funder: only owner");
        funder.setAuthorizedCaller(user2, true);
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    EMERGENCY WITHDRAW TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_emergencyWithdraw_transfersFunds() public {
        uint256 balance = 1 ether;
        uint256 withdrawAmount = 0.5 ether;
        
        vm.deal(address(funder), balance);
        
        // Create a receivable address (EOA) for withdrawal
        address payable recipient = payable(address(0x1234));
        vm.deal(recipient, 0);
        uint256 recipientBalanceBefore = recipient.balance;
        
        vm.expectEmit(true, false, false, true, address(funder));
        emit FundsWithdrawn(recipient, withdrawAmount);
        
        funder.emergencyWithdraw(recipient, withdrawAmount);
        
        assertEq(address(funder).balance, balance - withdrawAmount);
        assertEq(recipient.balance, recipientBalanceBefore + withdrawAmount);
    }
    
    function test_emergencyWithdraw_onlyOwner() public {
        vm.deal(address(funder), 1 ether);
        
        vm.prank(user1);
        vm.expectRevert("Funder: only owner");
        funder.emergencyWithdraw(payable(user1), 0.5 ether);
    }
    
    function test_emergencyWithdraw_revertsOnInsufficientBalance() public {
        vm.deal(address(funder), 0.1 ether);
        
        vm.expectRevert("Funder: insufficient balance");
        funder.emergencyWithdraw(payable(owner), 1 ether);
    }
    
    function test_emergencyWithdraw_revertsOnZeroAddress() public {
        vm.deal(address(funder), 1 ether);
        
        vm.expectRevert("Funder: zero address");
        funder.emergencyWithdraw(payable(address(0)), 0.5 ether);
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    VIEW FUNCTIONS TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_getBalance_returnsCorrectBalance() public {
        uint256 balance = 0.75 ether;
        vm.deal(address(funder), balance);
        assertEq(funder.getBalance(), balance);
    }
    
    function test_getStats_returnsCorrectValues() public {
        // Send some funds
        vm.prank(user1);
        funder.fund{value: 0.5 ether}();
        
        (
            uint256 totalCollected,
            uint256 totalBridged,
            uint256 currentBalance,
            uint256 threshold,
            uint256 bridgeCount,
            address rsc
        ) = funder.getStats();
        
        assertEq(totalCollected, 0.5 ether);
        assertEq(totalBridged, 0); // Nothing bridged yet
        assertEq(currentBalance, 0.5 ether);
        assertEq(threshold, 0.01 ether);
        assertEq(bridgeCount, 0);
        assertEq(rsc, targetRsc);
    }
    
    // ═══════════════════════════════════════════════════════════════
    //                    ACCUMULATION TESTS
    // ═══════════════════════════════════════════════════════════════
    
    function test_accumulation_multipleDeposits() public {
        uint256 deposit1 = 0.1 ether;
        uint256 deposit2 = 0.2 ether;
        uint256 deposit3 = 0.15 ether;
        
        vm.prank(user1);
        funder.fund{value: deposit1}();
        
        vm.prank(user2);
        funder.fund{value: deposit2}();
        
        vm.prank(user1);
        funder.fund{value: deposit3}();
        
        assertEq(funder.totalCollected(), deposit1 + deposit2 + deposit3);
        assertEq(address(funder).balance, deposit1 + deposit2 + deposit3);
    }
}
