// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/libraries/LeverageCalculator.sol";

/**
 * @title LeverageCalculatorFuzzTest
 * @notice Fuzz tests for LeverageCalculator library
 * @dev Tests invariants and properties with random inputs
 */
contract LeverageCalculatorFuzzTest is Test {
    // ═══════════════════════════════════════════════════════════════
    //                   LEVERAGE CALCULATION FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: Leverage should always be >= 1x with valid inputs
     */
    function testFuzz_calculateLeverage_alwaysGeOne(
        uint256 collateral,
        uint256 debt
    ) public pure {
        collateral = bound(collateral, 1e18, 1000000e18);
        debt = bound(debt, 0, collateral - 1);

        uint256 leverage = LeverageCalculator.calculateLeverage(collateral, debt);
        
        // Leverage should always be at least 1x (1e18)
        assertGe(leverage, 1e18, "Leverage should be at least 1x");
    }

    /**
     * @notice Fuzz: Zero debt should give 1x leverage
     */
    function testFuzz_calculateLeverage_zeroDebtIsOne(uint256 collateral) public pure {
        collateral = bound(collateral, 1e18, 1000000e18);

        uint256 leverage = LeverageCalculator.calculateLeverage(collateral, 0);
        assertEq(leverage, 1e18, "Zero debt should give exactly 1x leverage");
    }

    /**
     * @notice Fuzz: Leverage should increase with more debt
     */
    function testFuzz_leverage_increasesWithDebt(
        uint256 collateral,
        uint256 debt1,
        uint256 debt2
    ) public pure {
        collateral = bound(collateral, 10e18, 1000e18);
        debt1 = bound(debt1, 1e18, collateral / 3);
        debt2 = bound(debt2, debt1 + 1e17, collateral * 2 / 3);

        uint256 lev1 = LeverageCalculator.calculateLeverage(collateral, debt1);
        uint256 lev2 = LeverageCalculator.calculateLeverage(collateral, debt2);

        assertGt(lev2, lev1, "More debt should give higher leverage");
    }

    /**
     * @notice Fuzz: Leverage formula correctness
     * @dev Leverage = Collateral / (Collateral - Debt)
     */
    function testFuzz_leverage_formulaCorrect(
        uint256 collateral,
        uint256 debt
    ) public pure {
        collateral = bound(collateral, 1e18, 1000e18);
        debt = bound(debt, 0, collateral * 9 / 10);

        uint256 leverage = LeverageCalculator.calculateLeverage(collateral, debt);

        // Manual calculation
        uint256 expectedLeverage = debt == 0 ? 1e18 : (collateral * 1e18) / (collateral - debt);

        assertApproxEqRel(leverage, expectedLeverage, 1e15, "Leverage formula incorrect");
    }

    /**
     * @notice Fuzz: Underwater positions return max uint256
     */
    function testFuzz_leverage_underwaterIsMax(
        uint256 collateral
    ) public pure {
        collateral = bound(collateral, 1e18, 1000e18);
        uint256 debt = collateral; // Equal to collateral = underwater

        uint256 leverage = LeverageCalculator.calculateLeverage(collateral, debt);
        assertEq(leverage, type(uint256).max, "Underwater should return max");
    }

    // ═══════════════════════════════════════════════════════════════
    //                   FLASH LOAN AMOUNT FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: Flash loan amount should be positive for leverage > 1x
     */
    function testFuzz_flashLoanAmount_positiveForLeverage(
        uint256 initialCollateral,
        uint256 targetLeverage
    ) public pure {
        initialCollateral = bound(initialCollateral, 1e18, 100e18);
        targetLeverage = bound(targetLeverage, 1e18 + 1, 10e18);

        uint256 flashAmount = LeverageCalculator.calculateFlashLoanAmount(
            initialCollateral,
            targetLeverage
        );

        assertGt(flashAmount, 0, "Flash loan should be positive for leverage > 1x");
    }

    /**
     * @notice Fuzz: Flash loan amount should be 0 for 1x leverage
     */
    function testFuzz_flashLoanAmount_zeroForOneLeverage(
        uint256 initialCollateral
    ) public pure {
        initialCollateral = bound(initialCollateral, 1e18, 100e18);

        uint256 flashAmount = LeverageCalculator.calculateFlashLoanAmount(
            initialCollateral,
            1e18 // 1x leverage
        );

        assertEq(flashAmount, 0, "Flash loan should be 0 for 1x leverage");
    }

    /**
     * @notice Fuzz: Flash loan amount formula correctness
     * @dev FlashAmount = (TargetLeverage - 1) * InitialCollateral
     */
    function testFuzz_flashLoanAmount_formulaCorrect(
        uint256 initialCollateral,
        uint256 targetLeverage
    ) public pure {
        initialCollateral = bound(initialCollateral, 1e18, 100e18);
        targetLeverage = bound(targetLeverage, 1e18, 10e18);

        uint256 flashAmount = LeverageCalculator.calculateFlashLoanAmount(
            initialCollateral,
            targetLeverage
        );

        // Manual calculation
        uint256 multiplier = targetLeverage - 1e18;
        uint256 expectedFlash = (initialCollateral * multiplier) / 1e18;

        assertEq(flashAmount, expectedFlash, "Flash loan formula incorrect");
    }

    // Note: Revert tests for excessive leverage are covered in unit tests
    // Internal library require statements cannot be tested with vm.expectRevert

    // ═══════════════════════════════════════════════════════════════
    //                   SAFE BORROW FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: Safe borrow should not exceed collateral value
     */
    function testFuzz_safeBorrow_notExceedCollateral(
        uint256 collateralValue,
        uint256 ltv,
        uint256 safetyBuffer
    ) public pure {
        collateralValue = bound(collateralValue, 1e18, 1000e18);
        ltv = bound(ltv, 1000, 9000);
        safetyBuffer = bound(safetyBuffer, 5000, 10000);

        uint256 safeBorrow = LeverageCalculator.calculateSafeBorrow(
            collateralValue,
            ltv,
            safetyBuffer
        );

        assertLe(safeBorrow, collateralValue, "Safe borrow exceeds collateral");
    }

    /**
     * @notice Fuzz: Safe borrow increases with LTV
     */
    function testFuzz_safeBorrow_increasesWithLTV(
        uint256 collateralValue,
        uint256 ltv1,
        uint256 ltv2,
        uint256 safetyBuffer
    ) public pure {
        collateralValue = bound(collateralValue, 1e18, 1000e18);
        ltv1 = bound(ltv1, 1000, 5000);
        ltv2 = bound(ltv2, ltv1 + 100, 9000);
        safetyBuffer = bound(safetyBuffer, 5000, 10000);

        uint256 borrow1 = LeverageCalculator.calculateSafeBorrow(collateralValue, ltv1, safetyBuffer);
        uint256 borrow2 = LeverageCalculator.calculateSafeBorrow(collateralValue, ltv2, safetyBuffer);

        assertGt(borrow2, borrow1, "Higher LTV should give more borrow");
    }

    // ═══════════════════════════════════════════════════════════════
    //                   SAFE WITHDRAW FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: Safe withdraw should return all collateral when no debt
     */
    function testFuzz_safeWithdraw_allWhenNoDebt(
        uint256 totalCollateral,
        uint256 liquidationThreshold,
        uint256 targetHf
    ) public pure {
        totalCollateral = bound(totalCollateral, 1e18, 1000e18);
        liquidationThreshold = bound(liquidationThreshold, 7000, 9000);
        targetHf = bound(targetHf, 1.2e18, 2e18);

        uint256 safeWithdraw = LeverageCalculator.calculateSafeWithdraw(
            totalCollateral,
            0, // No debt
            liquidationThreshold,
            targetHf
        );

        assertEq(safeWithdraw, totalCollateral, "Should withdraw all when no debt");
    }

    /**
     * @notice Fuzz: Safe withdraw should maintain target HF
     */
    function testFuzz_safeWithdraw_maintainsTargetHf(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 liquidationThreshold,
        uint256 targetHf
    ) public pure {
        totalCollateral = bound(totalCollateral, 1e10, 1e18);
        totalDebt = bound(totalDebt, 1e9, totalCollateral / 3);
        liquidationThreshold = bound(liquidationThreshold, 7000, 9000);
        targetHf = bound(targetHf, 1.2e18, 2e18);

        uint256 safeWithdraw = LeverageCalculator.calculateSafeWithdraw(
            totalCollateral,
            totalDebt,
            liquidationThreshold,
            targetHf
        );

        if (safeWithdraw > 0 && safeWithdraw < totalCollateral) {
            uint256 newCollateral = totalCollateral - safeWithdraw;
            // HF = (Collateral * LT) / (Debt * BPS)
            uint256 newHf = (newCollateral * liquidationThreshold * 1e18) / (totalDebt * 10000);
            
            assertGe(newHf, targetHf * 95 / 100, "Withdrawal should maintain target HF");
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                   IS WITHIN TARGET FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: Equal leverage should always be within target
     */
    function testFuzz_isWithinTarget_equalIsWithin(
        uint256 leverage,
        uint256 tolerance
    ) public pure {
        leverage = bound(leverage, 1e18, 10e18);
        tolerance = bound(tolerance, 100, 1000);

        bool within = LeverageCalculator.isWithinTarget(leverage, leverage, tolerance);
        assertTrue(within, "Equal leverage should be within target");
    }

    /**
     * @notice Fuzz: Large deviation should not be within target
     */
    function testFuzz_isWithinTarget_largeDeviationNotWithin(
        uint256 leverage,
        uint256 target
    ) public pure {
        leverage = bound(leverage, 2e18, 5e18);
        target = bound(target, leverage * 2, leverage * 3);
        uint256 tolerance = 100; // 1%

        bool within = LeverageCalculator.isWithinTarget(leverage, target, tolerance);
        assertFalse(within, "Large deviation should not be within target");
    }

    // ═══════════════════════════════════════════════════════════════
    //                   VALIDATE LEVERAGE FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: Valid leverage range (1x to 10x) should pass
     */
    function testFuzz_validateLeverage_validRange(uint256 leverage) public pure {
        leverage = bound(leverage, 1e18, 10e18);

        bool valid = LeverageCalculator.validateLeverage(leverage);
        assertTrue(valid, "Leverage in valid range should pass");
    }

    /**
     * @notice Fuzz: Leverage below 1x should fail
     */
    function testFuzz_validateLeverage_belowMinFails(uint256 leverage) public pure {
        leverage = bound(leverage, 0, 1e18 - 1);

        bool valid = LeverageCalculator.validateLeverage(leverage);
        assertFalse(valid, "Leverage below 1x should fail");
    }

    /**
     * @notice Fuzz: Leverage above 10x should fail
     */
    function testFuzz_validateLeverage_aboveMaxFails(uint256 leverage) public pure {
        leverage = bound(leverage, 10e18 + 1, 100e18);

        bool valid = LeverageCalculator.validateLeverage(leverage);
        assertFalse(valid, "Leverage above 10x should fail");
    }

    // ═══════════════════════════════════════════════════════════════
    //                   ESTIMATE ITERATIONS FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: Already at target should return 0 iterations
     */
    function testFuzz_estimateIterations_atTargetIsZero(
        uint256 leverage,
        uint256 ltv
    ) public pure {
        leverage = bound(leverage, 1e18, 5e18);
        ltv = bound(ltv, 5000, 8500);

        uint256 iterations = LeverageCalculator.estimateIterations(leverage, leverage, ltv);
        assertEq(iterations, 0, "At target should need 0 iterations");
    }

    /**
     * @notice Fuzz: Above target should return 0 iterations
     */
    function testFuzz_estimateIterations_aboveTargetIsZero(
        uint256 current,
        uint256 target,
        uint256 ltv
    ) public pure {
        target = bound(target, 1e18, 3e18);
        current = bound(current, target + 1e17, target * 2);
        ltv = bound(ltv, 5000, 8500);

        uint256 iterations = LeverageCalculator.estimateIterations(current, target, ltv);
        assertEq(iterations, 0, "Above target should need 0 iterations");
    }

    /**
     * @notice Fuzz: Below target should need > 0 iterations
     */
    function testFuzz_estimateIterations_belowTargetNeedsIterations(
        uint256 current,
        uint256 target,
        uint256 ltv
    ) public pure {
        current = bound(current, 1e18, 2e18);
        target = bound(target, current + 1e17, current * 3);
        ltv = bound(ltv, 5000, 8500);

        uint256 iterations = LeverageCalculator.estimateIterations(current, target, ltv);
        assertGt(iterations, 0, "Below target should need iterations");
    }

    /**
     * @notice Fuzz: Iterations should be bounded
     */
    function testFuzz_estimateIterations_bounded(
        uint256 current,
        uint256 target,
        uint256 ltv
    ) public pure {
        current = bound(current, 1e18, 2e18);
        target = bound(target, current + 1e17, 100e18);
        ltv = bound(ltv, 5000, 8500);

        uint256 iterations = LeverageCalculator.estimateIterations(current, target, ltv);
        assertLe(iterations, 20, "Iterations should not exceed 20");
    }
}
