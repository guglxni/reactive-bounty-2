// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/libraries/HealthFactorLib.sol";

/**
 * @title HealthFactorLibFuzzTest
 * @notice Fuzz tests for HealthFactorLib library
 * @dev Tests invariants and edge cases with random inputs
 */
contract HealthFactorLibFuzzTest is Test {
    // ═══════════════════════════════════════════════════════════════
    //                   HEALTH FACTOR CALCULATION FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: Health factor should always be positive with valid inputs
     */
    function testFuzz_calculateHealthFactor_alwaysPositive(
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 liquidationThreshold
    ) public pure {
        // Bound to valid ranges
        totalCollateralBase = bound(totalCollateralBase, 1e8, 1e20); // $1 to $1T in 8 decimals
        totalDebtBase = bound(totalDebtBase, 1e8, totalCollateralBase);
        liquidationThreshold = bound(liquidationThreshold, 5000, 9500);

        uint256 hf = HealthFactorLib.calculateHealthFactor(
            totalCollateralBase,
            totalDebtBase,
            liquidationThreshold
        );

        assertGt(hf, 0, "Health factor should always be positive");
    }

    /**
     * @notice Fuzz: Zero debt should return max uint256
     */
    function testFuzz_calculateHealthFactor_zeroDebtIsMax(
        uint256 totalCollateralBase,
        uint256 liquidationThreshold
    ) public pure {
        totalCollateralBase = bound(totalCollateralBase, 1e8, 1e20);
        liquidationThreshold = bound(liquidationThreshold, 5000, 9500);

        uint256 hf = HealthFactorLib.calculateHealthFactor(
            totalCollateralBase,
            0,
            liquidationThreshold
        );

        assertEq(hf, type(uint256).max, "Zero debt should return max health factor");
    }

    /**
     * @notice Fuzz: HF formula correctness check
     * @dev HF = (collateral * LT / 10000) / debt
     */
    function testFuzz_calculateHealthFactor_formulaCorrect(
        uint256 collateral,
        uint256 debt,
        uint256 lt
    ) public pure {
        collateral = bound(collateral, 1e8, 1e18);
        debt = bound(debt, 1e8, collateral);
        lt = bound(lt, 5000, 9500);

        uint256 hf = HealthFactorLib.calculateHealthFactor(collateral, debt, lt);

        // Manual calculation: HF = (collateral * lt * 1e18) / (debt * 10000)
        uint256 expectedHf = (collateral * lt * 1e18) / (debt * 10000);

        // Allow small tolerance for rounding
        assertApproxEqRel(hf, expectedHf, 1e15, "Health factor formula incorrect");
    }

    // ═══════════════════════════════════════════════════════════════
    //                   IS SAFE FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: isSafe returns true when HF >= min threshold
     */
    function testFuzz_isSafe_aboveThreshold(
        uint256 hf,
        uint256 minHf
    ) public pure {
        minHf = bound(minHf, 1e18, 2e18); // 1.0 to 2.0
        hf = bound(hf, minHf, 10e18);

        bool safe = HealthFactorLib.isSafe(hf, minHf);
        assertTrue(safe, "Should be safe when HF >= minimum");
    }

    /**
     * @notice Fuzz: isSafe returns false when HF < min threshold
     */
    function testFuzz_isSafe_belowThreshold(
        uint256 minHf
    ) public pure {
        minHf = bound(minHf, 1.1e18, 2e18);
        uint256 hf = minHf - 1e16; // Just below threshold

        bool safe = HealthFactorLib.isSafe(hf, minHf);
        assertFalse(safe, "Should not be safe when HF < minimum");
    }

    // ═══════════════════════════════════════════════════════════════
    //                   IS CRITICAL FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: isCritical returns true when HF < critical threshold (1.05)
     */
    function testFuzz_isCritical_belowCritical(uint256 hf) public pure {
        hf = bound(hf, 1e17, 1.05e18 - 1);

        bool critical = HealthFactorLib.isCritical(hf);
        assertTrue(critical, "Should be critical when HF < 1.05");
    }

    /**
     * @notice Fuzz: isCritical returns false when HF >= critical threshold
     */
    function testFuzz_isCritical_aboveCritical(uint256 hf) public pure {
        hf = bound(hf, 1.05e18, 5e18);

        bool critical = HealthFactorLib.isCritical(hf);
        assertFalse(critical, "Should not be critical when HF >= 1.05");
    }

    // ═══════════════════════════════════════════════════════════════
    //                   CAN BE LIQUIDATED FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: canBeLiquidated returns true when HF < 1.0
     */
    function testFuzz_canBeLiquidated_belowOne(uint256 hf) public pure {
        hf = bound(hf, 1e17, 1e18 - 1);

        bool canLiq = HealthFactorLib.canBeLiquidated(hf);
        assertTrue(canLiq, "Should be liquidatable when HF < 1.0");
    }

    /**
     * @notice Fuzz: canBeLiquidated returns false when HF >= 1.0
     */
    function testFuzz_canBeLiquidated_aboveOne(uint256 hf) public pure {
        hf = bound(hf, 1e18, 5e18);

        bool canLiq = HealthFactorLib.canBeLiquidated(hf);
        assertFalse(canLiq, "Should not be liquidatable when HF >= 1.0");
    }

    // ═══════════════════════════════════════════════════════════════
    //                   GET URGENCY LEVEL FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: getUrgencyLevel returns correct levels
     */
    function testFuzz_getUrgencyLevel_correctLevels(uint256 hf) public pure {
        hf = bound(hf, 1e17, 5e18);

        uint8 level = HealthFactorLib.getUrgencyLevel(hf);

        if (hf >= 1.1e18) {
            assertEq(level, 0, "Should be Safe (0) when HF >= 1.1");
        } else if (hf >= 1.05e18) {
            assertEq(level, 1, "Should be Warning (1) when 1.05 <= HF < 1.1");
        } else if (hf >= 1e18) {
            assertEq(level, 2, "Should be Critical (2) when 1.0 <= HF < 1.05");
        } else {
            assertEq(level, 3, "Should be Liquidatable (3) when HF < 1.0");
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                   CALCULATE MAX BORROW FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: Max borrow should maintain target HF
     */
    function testFuzz_calculateMaxBorrow_maintainsTargetHf(
        uint256 totalCollateralBase,
        uint256 currentDebtBase,
        uint256 liquidationThreshold,
        uint256 targetHf
    ) public pure {
        totalCollateralBase = bound(totalCollateralBase, 1e10, 1e18);
        currentDebtBase = bound(currentDebtBase, 0, totalCollateralBase / 4);
        liquidationThreshold = bound(liquidationThreshold, 7000, 9000);
        targetHf = bound(targetHf, 1.2e18, 2e18);

        uint256 maxBorrow = HealthFactorLib.calculateMaxBorrow(
            totalCollateralBase,
            currentDebtBase,
            liquidationThreshold,
            targetHf
        );

        if (maxBorrow > 0) {
            uint256 newDebt = currentDebtBase + maxBorrow;
            uint256 newHf = HealthFactorLib.calculateHealthFactor(
                totalCollateralBase,
                newDebt,
                liquidationThreshold
            );

            // HF after borrow should be approximately at target
            assertGe(newHf, targetHf * 95 / 100, "Borrow should maintain target HF");
        }
    }

    /**
     * @notice Fuzz: Max borrow returns 0 when already too leveraged
     */
    function testFuzz_calculateMaxBorrow_zeroWhenOverLeveraged(
        uint256 totalCollateralBase,
        uint256 liquidationThreshold,
        uint256 targetHf
    ) public pure {
        totalCollateralBase = bound(totalCollateralBase, 1e10, 1e18);
        liquidationThreshold = bound(liquidationThreshold, 8000, 8500);
        targetHf = bound(targetHf, 1.2e18, 1.5e18);

        // Set debt so HF is already at or below target
        // debt = (col * lt) / (targetHf * 10000)
        uint256 currentDebtBase = (totalCollateralBase * liquidationThreshold * 1e18) / (targetHf * 10000);
        currentDebtBase = currentDebtBase * 101 / 100; // Slightly over

        uint256 maxBorrow = HealthFactorLib.calculateMaxBorrow(
            totalCollateralBase,
            currentDebtBase,
            liquidationThreshold,
            targetHf
        );

        assertEq(maxBorrow, 0, "Should return 0 when already at/below target HF");
    }

    // ═══════════════════════════════════════════════════════════════
    //                   CALCULATE REPAY TO RESTORE FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: Repay amount should restore target HF
     */
    function testFuzz_calculateRepayToRestore_restoresTargetHf(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 liquidationThreshold,
        uint256 targetHf
    ) public pure {
        totalCollateral = bound(totalCollateral, 1e10, 1e18);
        liquidationThreshold = bound(liquidationThreshold, 7000, 9000);
        targetHf = bound(targetHf, 1.2e18, 2e18);
        
        // Make debt high enough to need repayment
        uint256 maxDebt = (totalCollateral * liquidationThreshold * 1e18) / (targetHf * 10000);
        totalDebt = bound(totalDebt, maxDebt + 1e8, maxDebt * 2);

        uint256 repayAmount = HealthFactorLib.calculateRepayToRestore(
            totalCollateral,
            totalDebt,
            liquidationThreshold,
            targetHf
        );

        if (repayAmount > 0 && repayAmount < totalDebt) {
            uint256 newDebt = totalDebt - repayAmount;
            uint256 newHf = HealthFactorLib.calculateHealthFactor(
                totalCollateral,
                newDebt,
                liquidationThreshold
            );

            // New HF should be approximately at target
            assertApproxEqRel(newHf, targetHf, 1e16, "Repay should restore target HF");
        }
    }

    /**
     * @notice Fuzz: Repay returns 0 when already above target
     */
    function testFuzz_calculateRepayToRestore_zeroWhenHealthy(
        uint256 totalCollateral,
        uint256 liquidationThreshold,
        uint256 targetHf
    ) public pure {
        totalCollateral = bound(totalCollateral, 1e10, 1e18);
        liquidationThreshold = bound(liquidationThreshold, 7000, 9000);
        targetHf = bound(targetHf, 1.2e18, 1.5e18);

        // Set debt so HF is already above target
        uint256 maxDebt = (totalCollateral * liquidationThreshold * 1e18) / (targetHf * 10000);
        uint256 totalDebt = maxDebt / 2; // Well above target

        uint256 repayAmount = HealthFactorLib.calculateRepayToRestore(
            totalCollateral,
            totalDebt,
            liquidationThreshold,
            targetHf
        );

        assertEq(repayAmount, 0, "Should return 0 when already above target HF");
    }

    // ═══════════════════════════════════════════════════════════════
    //                   HF AFTER BORROW/SUPPLY FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: HF after borrow should decrease
     */
    function testFuzz_calculateHealthFactorAfterBorrow_decreases(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 borrowAmount,
        uint256 lt
    ) public pure {
        totalCollateral = bound(totalCollateral, 1e10, 1e18);
        totalDebt = bound(totalDebt, 1e8, totalCollateral / 3);
        borrowAmount = bound(borrowAmount, 1e8, totalDebt);
        lt = bound(lt, 7000, 9000);

        uint256 hfBefore = HealthFactorLib.calculateHealthFactor(totalCollateral, totalDebt, lt);
        uint256 hfAfter = HealthFactorLib.calculateHealthFactorAfterBorrow(
            totalCollateral, totalDebt, borrowAmount, lt
        );

        assertLt(hfAfter, hfBefore, "HF should decrease after borrowing");
    }

    /**
     * @notice Fuzz: HF after supply should increase
     */
    function testFuzz_calculateHealthFactorAfterSupply_increases(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 supplyAmount,
        uint256 lt
    ) public pure {
        totalCollateral = bound(totalCollateral, 1e10, 1e18);
        totalDebt = bound(totalDebt, 1e8, totalCollateral / 2);
        supplyAmount = bound(supplyAmount, 1e8, totalCollateral);
        lt = bound(lt, 7000, 9000);

        uint256 hfBefore = HealthFactorLib.calculateHealthFactor(totalCollateral, totalDebt, lt);
        uint256 hfAfter = HealthFactorLib.calculateHealthFactorAfterSupply(
            totalCollateral, totalDebt, supplyAmount, lt
        );

        assertGt(hfAfter, hfBefore, "HF should increase after supplying");
    }

    // ═══════════════════════════════════════════════════════════════
    //                   GET HEALTH FACTOR BUFFER FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: Buffer should be 0 when HF <= 1.0
     */
    function testFuzz_getHealthFactorBuffer_zeroWhenAtOrBelowOne(uint256 hf) public pure {
        hf = bound(hf, 1e17, 1e18);

        uint256 buffer = HealthFactorLib.getHealthFactorBuffer(hf);
        assertEq(buffer, 0, "Buffer should be 0 when HF <= 1.0");
    }

    /**
     * @notice Fuzz: Buffer should match (HF - 1) * 10000
     */
    function testFuzz_getHealthFactorBuffer_correctValue(uint256 hf) public pure {
        hf = bound(hf, 1e18 + 1, 3e18);

        uint256 buffer = HealthFactorLib.getHealthFactorBuffer(hf);
        uint256 expectedBuffer = ((hf - 1e18) * 10000) / 1e18;

        assertEq(buffer, expectedBuffer, "Buffer calculation incorrect");
    }

    // ═══════════════════════════════════════════════════════════════
    //                   INVARIANT TESTS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Fuzz: HF monotonicity - increasing collateral increases HF
     */
    function testFuzz_invariant_hfMonotonicWithCollateral(
        uint256 col1,
        uint256 debt,
        uint256 lt
    ) public pure {
        debt = bound(debt, 1e8, 1e16);
        col1 = bound(col1, debt * 2, debt * 10);
        uint256 col2 = col1 + 1e8;
        lt = bound(lt, 7000, 9000);

        uint256 hf1 = HealthFactorLib.calculateHealthFactor(col1, debt, lt);
        uint256 hf2 = HealthFactorLib.calculateHealthFactor(col2, debt, lt);

        assertGt(hf2, hf1, "HF should increase with collateral");
    }

    /**
     * @notice Fuzz: HF monotonicity - decreasing debt increases HF
     */
    function testFuzz_invariant_hfMonotonicWithDebt(
        uint256 col,
        uint256 debt1,
        uint256 lt
    ) public pure {
        col = bound(col, 1e10, 1e18);
        debt1 = bound(debt1, 1e9, col / 2);
        uint256 debt2 = debt1 - 1e8;
        lt = bound(lt, 7000, 9000);

        uint256 hf1 = HealthFactorLib.calculateHealthFactor(col, debt1, lt);
        uint256 hf2 = HealthFactorLib.calculateHealthFactor(col, debt2, lt);

        assertGt(hf2, hf1, "HF should increase when debt decreases");
    }

    /**
     * @notice Fuzz: HF at liquidation threshold boundary
     * @dev When debt = collateral * LT / 10000, HF should be exactly 1.0
     */
    function testFuzz_invariant_hfAtLiquidationBoundary(
        uint256 col,
        uint256 lt
    ) public pure {
        col = bound(col, 1e12, 1e18);
        lt = bound(lt, 7000, 9000);

        // debt = col * lt / 10000 gives HF = 1.0
        uint256 debtAtBoundary = (col * lt) / 10000;

        uint256 hf = HealthFactorLib.calculateHealthFactor(col, debtAtBoundary, lt);

        // HF should be approximately 1e18 (1.0)
        assertApproxEqRel(hf, 1e18, 1e15, "HF should be 1.0 at liquidation boundary");
    }
}
