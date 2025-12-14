// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/AutoLooperReactive.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";

/**
 * @title AutoLooperReactiveTest
 * @notice Comprehensive tests for AutoLooperReactive contract
 * @dev Tests react() logic, callback emission, and state handling
 */
contract AutoLooperReactiveTest is Test {
    // ═══════════════════════════════════════════════════════════════
    //                       TEST SETUP
    // ═══════════════════════════════════════════════════════════════

    AutoLooperReactive public reactive;
    
    // Test addresses
    address public vault = address(0xABCD);
    address public user = address(0x1234);
    
    // Chain IDs
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    
    // Constants matching the contract
    uint256 private constant POSITION_UPDATED_TOPIC_0 = 
        0xd97440db9c04f33925d0d4f3a9762d3e70c867b5d7e193cb11897e63c88f10de;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1.1e18;
    
    // Position states
    uint8 private constant STATE_IDLE = 0;
    uint8 private constant STATE_LOOPING = 1;
    uint8 private constant STATE_UNWINDING = 2;
    uint8 private constant STATE_EMERGENCY = 3;

    // Events from AutoLooperReactive
    event LoopCallbackTriggered(address indexed user, uint256 currentLeverage, uint256 targetLeverage);
    event UnwindCallbackTriggered(address indexed user, uint256 currentLeverage, uint256 healthFactor);
    event Callback(uint256 indexed chainId, address indexed target, uint64 indexed gasLimit, bytes payload);

    function setUp() public {
        // Deploy with vm=true (simulated environment)
        // In tests, we need to handle that AbstractReactive sets vm=true based on chain ID
        vm.chainId(5318007); // Lasna chain ID
        reactive = new AutoLooperReactive(vault, SEPOLIA_CHAIN_ID);
    }

    // ═══════════════════════════════════════════════════════════════
    //                  CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════

    function test_constructor_setsVault() public view {
        assertEq(reactive.getVault(), vault, "Vault should be set correctly");
    }

    function test_constructor_setsChainId() public view {
        assertEq(reactive.getChainId(), SEPOLIA_CHAIN_ID, "Chain ID should be Sepolia");
    }

    // ═══════════════════════════════════════════════════════════════
    //                  REACT FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════

    function test_react_ignoresWrongContract() public {
        // Create log from wrong contract
        IReactive.LogRecord memory log = _createLogRecord(
            address(0xDEAD), // Wrong contract
            user,
            1.5e18, // currentLeverage
            2.0e18, // targetLeverage
            1.5e18, // healthFactor
            0,      // iteration
            STATE_LOOPING
        );

        // Should not emit any events
        vm.recordLogs();
        reactive.react(log);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Filter for our events (not the default Callback event)
        uint256 callbackCount = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Callback(uint256,address,uint64,bytes)")) {
                callbackCount++;
            }
        }
        assertEq(callbackCount, 0, "Should not emit callback for wrong contract");
    }

    function test_react_ignoresWrongTopic() public {
        // Create log with wrong topic
        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: SEPOLIA_CHAIN_ID,
            _contract: vault,
            topic_0: 0x1234, // Wrong topic
            topic_1: uint256(uint160(user)),
            topic_2: 0,
            topic_3: 0,
            data: abi.encode(1.5e18, 2.0e18, 1.5e18, uint256(0), uint8(STATE_LOOPING)),
            block_number: block.number,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        vm.recordLogs();
        reactive.react(log);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        uint256 callbackCount = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Callback(uint256,address,uint64,bytes)")) {
                callbackCount++;
            }
        }
        assertEq(callbackCount, 0, "Should not emit callback for wrong topic");
    }

    // ═══════════════════════════════════════════════════════════════
    //                  LOOPING STATE TESTS
    // ═══════════════════════════════════════════════════════════════

    function test_react_loopingState_emitsLoopCallback() public {
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            1.5e18, // currentLeverage (1.5x)
            2.0e18, // targetLeverage (2.0x)
            1.5e18, // healthFactor (healthy)
            0,      // iteration
            STATE_LOOPING
        );

        vm.expectEmit(true, false, false, true);
        emit LoopCallbackTriggered(user, 1.5e18, 2.0e18);

        reactive.react(log);
    }

    function test_react_loopingState_targetReached_noCallback() public {
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            2.0e18, // currentLeverage = targetLeverage
            2.0e18, // targetLeverage
            1.5e18, // healthFactor
            5,      // iteration
            STATE_LOOPING
        );

        vm.recordLogs();
        reactive.react(log);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Should have no LoopCallbackTriggered event
        bool foundLoopEvent = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("LoopCallbackTriggered(address,uint256,uint256)")) {
                foundLoopEvent = true;
            }
        }
        assertFalse(foundLoopEvent, "Should not emit loop callback when target reached");
    }

    function test_react_loopingState_exceedsTarget_noCallback() public {
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            2.5e18, // currentLeverage exceeds target
            2.0e18, // targetLeverage
            1.5e18, // healthFactor
            5,      // iteration
            STATE_LOOPING
        );

        vm.recordLogs();
        reactive.react(log);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        bool foundLoopEvent = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("LoopCallbackTriggered(address,uint256,uint256)")) {
                foundLoopEvent = true;
            }
        }
        assertFalse(foundLoopEvent, "Should not emit loop callback when exceeds target");
    }

    function test_react_loopingState_maxIterationsReached_noCallback() public {
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            1.5e18, // currentLeverage
            2.0e18, // targetLeverage
            1.5e18, // healthFactor
            15,     // iteration = MAX_ITERATIONS
            STATE_LOOPING
        );

        vm.recordLogs();
        reactive.react(log);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        bool foundLoopEvent = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("LoopCallbackTriggered(address,uint256,uint256)")) {
                foundLoopEvent = true;
            }
        }
        assertFalse(foundLoopEvent, "Should not emit loop callback at max iterations");
    }

    // ═══════════════════════════════════════════════════════════════
    //                  UNWINDING STATE TESTS
    // ═══════════════════════════════════════════════════════════════

    function test_react_unwindingState_emitsUnwindCallback() public {
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            1.5e18, // currentLeverage > 1x
            1.0e18, // targetLeverage (1x = fully unwound)
            1.5e18, // healthFactor
            0,      // iteration
            STATE_UNWINDING
        );

        vm.recordLogs();
        reactive.react(log);
        
        // Should emit unwind callback (Callback event)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundCallback = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Callback(uint256,address,uint64,bytes)")) {
                foundCallback = true;
            }
        }
        assertTrue(foundCallback, "Should emit callback when unwinding");
    }

    function test_react_unwindingState_fullyUnwound_noCallback() public {
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            1.0e18, // currentLeverage = 1x (fully unwound)
            1.0e18, // targetLeverage
            1.5e18, // healthFactor
            5,      // iteration
            STATE_UNWINDING
        );

        vm.recordLogs();
        reactive.react(log);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        uint256 callbackCount = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Callback(uint256,address,uint64,bytes)")) {
                callbackCount++;
            }
        }
        assertEq(callbackCount, 0, "Should not emit callback when fully unwound");
    }

    // ═══════════════════════════════════════════════════════════════
    //                  EMERGENCY STATE TESTS
    // ═══════════════════════════════════════════════════════════════

    function test_react_emergencyState_emitsUnwindCallback() public {
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            2.0e18, // currentLeverage
            1.0e18, // targetLeverage
            1.5e18, // healthFactor (healthy, but emergency state)
            0,      // iteration
            STATE_EMERGENCY
        );

        vm.recordLogs();
        reactive.react(log);
        
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundCallback = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Callback(uint256,address,uint64,bytes)")) {
                foundCallback = true;
            }
        }
        assertTrue(foundCallback, "Should emit callback in emergency state");
    }

    function test_react_emergencyState_fullyUnwound_noCallback() public {
        // When fully unwound (1x leverage), even in emergency with low HF,
        // the health factor check runs first but the emergency handler
        // still checks leverage - at 1x it should not emit callback
        // Actually: The HF check triggers unwind callback because HF < MIN
        // This is expected behavior: try to improve HF until safe
        // 
        // Let's test with HEALTHY HF and emergency state at 1x leverage
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            1.0e18, // currentLeverage = 1x
            1.0e18, // targetLeverage
            1.5e18, // healthFactor (HEALTHY - above MIN)
            10,     // iteration
            STATE_EMERGENCY
        );

        vm.recordLogs();
        reactive.react(log);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        uint256 callbackCount = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Callback(uint256,address,uint64,bytes)")) {
                callbackCount++;
            }
        }
        assertEq(callbackCount, 0, "Should not emit callback when fully unwound in emergency with healthy HF");
    }

    function test_react_emergencyState_lowHF_stillEmitsCallback() public {
        // Even at 1x leverage, if HF is low, system should try to unwind further
        // This is the safety behavior - keep trying until HF improves
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            1.0e18, // currentLeverage = 1x
            1.0e18, // targetLeverage
            0.8e18, // healthFactor (LOW - below MIN)
            10,     // iteration
            STATE_EMERGENCY
        );

        // Should emit UnwindCallbackTriggered because HF is low
        vm.expectEmit(true, false, false, true);
        emit UnwindCallbackTriggered(user, 1.0e18, 0.8e18);

        reactive.react(log);
    }

    // ═══════════════════════════════════════════════════════════════
    //                  HEALTH FACTOR TESTS
    // ═══════════════════════════════════════════════════════════════

    function test_react_lowHealthFactor_triggersEmergencyUnwind() public {
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            2.0e18,        // currentLeverage
            3.0e18,        // targetLeverage (was looping to get more)
            1.05e18,       // healthFactor < MIN_HEALTH_FACTOR (1.1)
            5,             // iteration
            STATE_LOOPING  // Was looping, but HF dropped
        );

        vm.expectEmit(true, false, false, true);
        emit UnwindCallbackTriggered(user, 2.0e18, 1.05e18);

        reactive.react(log);
    }

    function test_react_lowHealthFactor_idleState_noAction() public {
        // If state is IDLE, don't emergency unwind even with low HF
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            1.0e18,        // currentLeverage = 1x
            1.0e18,        // targetLeverage
            1.05e18,       // healthFactor < MIN (but position is closed)
            0,             // iteration
            STATE_IDLE     // Position is idle
        );

        vm.recordLogs();
        reactive.react(log);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        uint256 callbackCount = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Callback(uint256,address,uint64,bytes)")) {
                callbackCount++;
            }
        }
        assertEq(callbackCount, 0, "Should not emit callback for IDLE state even with low HF");
    }

    function test_react_healthyHealthFactor_continuesLooping() public {
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            1.5e18, // currentLeverage
            2.0e18, // targetLeverage
            1.5e18, // healthFactor > MIN (healthy)
            3,      // iteration
            STATE_LOOPING
        );

        vm.expectEmit(true, false, false, true);
        emit LoopCallbackTriggered(user, 1.5e18, 2.0e18);

        reactive.react(log);
    }

    // ═══════════════════════════════════════════════════════════════
    //                  IDLE STATE TESTS
    // ═══════════════════════════════════════════════════════════════

    function test_react_idleState_noCallback() public {
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            1.0e18, // currentLeverage
            1.0e18, // targetLeverage
            2.0e18, // healthFactor
            0,      // iteration
            STATE_IDLE
        );

        vm.recordLogs();
        reactive.react(log);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        uint256 callbackCount = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Callback(uint256,address,uint64,bytes)")) {
                callbackCount++;
            }
        }
        assertEq(callbackCount, 0, "Should not emit callback for IDLE state");
    }

    // ═══════════════════════════════════════════════════════════════
    //                  CALLBACK PAYLOAD TESTS
    // ═══════════════════════════════════════════════════════════════

    function test_loopCallback_hasCorrectPayload() public {
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            1.5e18, // currentLeverage
            2.0e18, // targetLeverage
            1.5e18, // healthFactor
            0,      // iteration
            STATE_LOOPING
        );

        vm.recordLogs();
        reactive.react(log);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find the Callback event
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Callback(uint256,address,uint64,bytes)")) {
                // Verify chain ID in topic
                assertEq(logs[i].topics[1], bytes32(uint256(SEPOLIA_CHAIN_ID)), "Chain ID should be Sepolia");
                // Verify target in topic
                assertEq(logs[i].topics[2], bytes32(uint256(uint160(vault))), "Target should be vault");
                
                // Decode payload from data
                bytes memory payload = abi.decode(logs[i].data, (bytes));
                
                // Verify it starts with executeLoopStep selector
                bytes4 selector = bytes4(payload);
                assertEq(selector, bytes4(keccak256("executeLoopStep(address,address)")), "Should call executeLoopStep");
                break;
            }
        }
    }

    function test_unwindCallback_hasCorrectPayload() public {
        IReactive.LogRecord memory log = _createLogRecord(
            vault,
            user,
            1.5e18, // currentLeverage
            1.0e18, // targetLeverage
            1.5e18, // healthFactor
            0,      // iteration
            STATE_UNWINDING
        );

        vm.recordLogs();
        reactive.react(log);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find the Callback event
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Callback(uint256,address,uint64,bytes)")) {
                bytes memory payload = abi.decode(logs[i].data, (bytes));
                bytes4 selector = bytes4(payload);
                assertEq(selector, bytes4(keccak256("executeUnwindStep(address,address)")), "Should call executeUnwindStep");
                break;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                     HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    function _createLogRecord(
        address _contract,
        address _user,
        uint256 _currentLeverage,
        uint256 _targetLeverage,
        uint256 _healthFactor,
        uint256 _iteration,
        uint8 _state
    ) internal view returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chain_id: SEPOLIA_CHAIN_ID,
            _contract: _contract,
            topic_0: POSITION_UPDATED_TOPIC_0,
            topic_1: uint256(uint160(_user)),
            topic_2: 0,
            topic_3: 0,
            data: abi.encode(_currentLeverage, _targetLeverage, _healthFactor, _iteration, _state),
            block_number: block.number,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });
    }
}
