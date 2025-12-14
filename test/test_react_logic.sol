// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TestReactLogic {
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1.1e18;
    uint256 private constant MAX_ITERATIONS = 50;
    
    uint8 private constant STATE_IDLE = 0;
    uint8 private constant STATE_LOOPING = 1;
    uint8 private constant STATE_UNWINDING = 2;
    uint8 private constant STATE_EMERGENCY = 3;
    
    function shouldEmitLoopCallback(
        uint256 currentLeverage,
        uint256 targetLeverage,
        uint256 healthFactor,
        uint256 iteration,
        uint8 state
    ) public pure returns (bool shouldCallback, string memory reason) {
        // Safety check: Emergency if health factor too low
        if (healthFactor < MIN_HEALTH_FACTOR && state != STATE_IDLE) {
            return (true, "Emergency: Low HF - emit unwind callback");
        }
        
        if (state == STATE_LOOPING) {
            // Check if target reached
            if (currentLeverage >= targetLeverage) {
                return (false, "LOOPING: Target reached");
            }
            // Check iteration limit
            if (iteration >= MAX_ITERATIONS) {
                return (false, "LOOPING: Max iterations reached");
            }
            // Continue looping
            return (true, "LOOPING: Should emit loop callback");
        }
        
        return (false, "Not in LOOPING state");
    }
}
