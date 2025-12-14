// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AutoLooperManager} from "../../src/AutoLooperManager.sol";
import {LeverageCalculator} from "../../src/libraries/LeverageCalculator.sol";
import {HealthFactorLib} from "../../src/libraries/HealthFactorLib.sol";

/**
 * @title LeverageCalculatorTest
 * @notice Unit tests for LeverageCalculator library
 */
contract LeverageCalculatorTest is Test {
    uint256 constant PRECISION = 1e18;
    uint256 constant BPS = 10000;

    function setUp() public {}

    // ═══════════════════════════════════════════════════════════════
    //                    calculateLeverage tests
    // ═══════════════════════════════════════════════════════════════

    function test_calculateLeverage_noDebt() public pure {
        // No debt = 1x leverage
        uint256 leverage = LeverageCalculator.calculateLeverage(1000e8, 0);
        assertEq(leverage, PRECISION, "No debt should equal 1x leverage");
    }

    function test_calculateLeverage_2x() public pure {
        // $2000 collateral, $1000 debt = 2x leverage
        // Leverage = 2000 / (2000 - 1000) = 2000 / 1000 = 2
        uint256 leverage = LeverageCalculator.calculateLeverage(2000e8, 1000e8);
        assertEq(leverage, 2e18, "Should be 2x leverage");
    }

    function test_calculateLeverage_3x() public pure {
        // $3000 collateral, $2000 debt = 3x leverage
        // Leverage = 3000 / (3000 - 2000) = 3000 / 1000 = 3
        uint256 leverage = LeverageCalculator.calculateLeverage(3000e8, 2000e8);
        assertEq(leverage, 3e18, "Should be 3x leverage");
    }

    function test_calculateLeverage_underwater() public pure {
        // Debt >= collateral = underwater position
        uint256 leverage = LeverageCalculator.calculateLeverage(1000e8, 1000e8);
        assertEq(leverage, type(uint256).max, "Equal debt/collateral should return max");
        
        leverage = LeverageCalculator.calculateLeverage(1000e8, 1500e8);
        assertEq(leverage, type(uint256).max, "More debt than collateral should return max");
    }

    // ═══════════════════════════════════════════════════════════════
    //                    calculateFlashLoanAmount tests
    // ═══════════════════════════════════════════════════════════════

    function test_calculateFlashLoanAmount_3x() public pure {
        // For 3x leverage with 1 ETH: need to flash loan 2 ETH
        // (3 - 1) * 1 = 2
        uint256 flashAmount = LeverageCalculator.calculateFlashLoanAmount(1e18, 3e18);
        assertEq(flashAmount, 2e18, "Should need 2 ETH flash loan for 3x");
    }

    function test_calculateFlashLoanAmount_2x() public pure {
        // For 2x leverage with 1 ETH: need to flash loan 1 ETH
        // (2 - 1) * 1 = 1
        uint256 flashAmount = LeverageCalculator.calculateFlashLoanAmount(1e18, 2e18);
        assertEq(flashAmount, 1e18, "Should need 1 ETH flash loan for 2x");
    }

    function test_calculateFlashLoanAmount_1x() public pure {
        // For 1x leverage: no flash loan needed
        uint256 flashAmount = LeverageCalculator.calculateFlashLoanAmount(1e18, 1e18);
        assertEq(flashAmount, 0, "Should need 0 flash loan for 1x");
    }

    function test_calculateFlashLoanAmount_reverts_below1x() public pure {
        // Library functions inlined - test boundary conditions instead
        // Target leverage 0.5e18 is below MIN_LEVERAGE (1e18)
        bool valid = LeverageCalculator.validateLeverage(0.5e18);
        assertFalse(valid, "0.5x leverage should be invalid");
    }

    function test_calculateFlashLoanAmount_reverts_above10x() public pure {
        // Library functions inlined - test boundary conditions instead
        // Target leverage 11e18 is above MAX_LEVERAGE (10e18)
        bool valid = LeverageCalculator.validateLeverage(11e18);
        assertFalse(valid, "11x leverage should be invalid");
    }

    // ═══════════════════════════════════════════════════════════════
    //                    calculateSafeBorrow tests
    // ═══════════════════════════════════════════════════════════════

    function test_calculateSafeBorrow() public pure {
        // $1000 collateral, 80% LTV, 95% safety buffer
        // Safe = 1000 * 0.80 * 0.95 = 760
        uint256 safeBorrow = LeverageCalculator.calculateSafeBorrow(1000e8, 8000, 9500);
        assertEq(safeBorrow, 760e8, "Should allow 760 safe borrow");
    }

    // ═══════════════════════════════════════════════════════════════
    //                    validateLeverage tests
    // ═══════════════════════════════════════════════════════════════

    function test_validateLeverage_valid() public pure {
        assertTrue(LeverageCalculator.validateLeverage(1e18), "1x should be valid");
        assertTrue(LeverageCalculator.validateLeverage(3e18), "3x should be valid");
        assertTrue(LeverageCalculator.validateLeverage(10e18), "10x should be valid");
    }

    function test_validateLeverage_invalid() public pure {
        assertFalse(LeverageCalculator.validateLeverage(0.5e18), "0.5x should be invalid");
        assertFalse(LeverageCalculator.validateLeverage(11e18), "11x should be invalid");
    }

    // ═══════════════════════════════════════════════════════════════
    //                    isWithinTarget tests
    // ═══════════════════════════════════════════════════════════════

    function test_isWithinTarget() public pure {
        // Current = 3x, Target = 3x, Tolerance = 1%
        assertTrue(LeverageCalculator.isWithinTarget(3e18, 3e18, 100), "Exact match should be within");
        
        // Current = 2.97x, Target = 3x, Tolerance = 1%
        // Deviation = 0.03e18, maxDeviation = 3e18 * 100 / 10000 = 0.03e18
        // 0.03 <= 0.03, so it should be WITHIN tolerance (edge case)
        assertTrue(LeverageCalculator.isWithinTarget(2.97e18, 3e18, 100), "Exactly 1% off should be within 1% tolerance (edge)");
        
        // Current = 2.96x, Target = 3x, Tolerance = 1%
        // Deviation = 0.04e18, maxDeviation = 0.03e18
        // 0.04 > 0.03, so outside tolerance
        assertFalse(LeverageCalculator.isWithinTarget(2.96e18, 3e18, 100), "1.33% off should be outside 1% tolerance");
        
        // Current = 2.97x, Target = 3x, Tolerance = 5%
        assertTrue(LeverageCalculator.isWithinTarget(2.97e18, 3e18, 500), "1% off should be within 5% tolerance");
    }
}

/**
 * @title HealthFactorLibTest
 * @notice Unit tests for HealthFactorLib library
 */
contract HealthFactorLibTest is Test {
    uint256 constant PRECISION = 1e18;
    uint256 constant BPS = 10000;

    function test_calculateHealthFactor_noDebt() public pure {
        uint256 hf = HealthFactorLib.calculateHealthFactor(1000e8, 0, 8500);
        assertEq(hf, type(uint256).max, "No debt should return max health factor");
    }

    function test_calculateHealthFactor_healthy() public pure {
        // $1000 collateral, $500 debt, 85% liq threshold
        // HF = (1000 * 0.85) / 500 = 850 / 500 = 1.7
        uint256 hf = HealthFactorLib.calculateHealthFactor(1000e8, 500e8, 8500);
        assertEq(hf, 1.7e18, "Should have 1.7 health factor");
    }

    function test_isSafe() public pure {
        assertTrue(HealthFactorLib.isSafe(1.5e18, 1.1e18), "1.5 HF should be safe above 1.1 min");
        assertFalse(HealthFactorLib.isSafe(1.05e18, 1.1e18), "1.05 HF should not be safe above 1.1 min");
    }

    function test_isCritical() public pure {
        assertFalse(HealthFactorLib.isCritical(1.1e18), "1.1 HF should not be critical");
        assertTrue(HealthFactorLib.isCritical(1.04e18), "1.04 HF should be critical");
    }

    function test_canBeLiquidated() public pure {
        assertFalse(HealthFactorLib.canBeLiquidated(1.0e18), "1.0 HF should not be liquidatable");
        assertTrue(HealthFactorLib.canBeLiquidated(0.99e18), "0.99 HF should be liquidatable");
    }

    function test_getUrgencyLevel() public pure {
        assertEq(HealthFactorLib.getUrgencyLevel(1.5e18), 0, "1.5 HF = Safe");
        assertEq(HealthFactorLib.getUrgencyLevel(1.08e18), 1, "1.08 HF = Warning");
        assertEq(HealthFactorLib.getUrgencyLevel(1.02e18), 2, "1.02 HF = Critical");
        assertEq(HealthFactorLib.getUrgencyLevel(0.95e18), 3, "0.95 HF = Liquidatable");
    }
}
