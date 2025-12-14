// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LeverageCalculator
 * @notice Library for leverage-related calculations
 * @dev All calculations use 18 decimal precision
 */
library LeverageCalculator {
    /// @notice Precision for leverage calculations (1e18 = 1x)
    uint256 constant PRECISION = 1e18;

    /// @notice Minimum leverage (1x = no leverage)
    uint256 constant MIN_LEVERAGE = 1e18;

    /// @notice Maximum leverage allowed (10x)
    uint256 constant MAX_LEVERAGE = 10e18;

    /// @notice Basis points denominator (100% = 10000)
    uint256 constant BPS = 10000;

    /**
     * @notice Calculate current leverage from collateral and debt
     * @dev Leverage = TotalCollateral / (TotalCollateral - TotalDebt)
     * @param totalCollateral Total collateral value in base currency
     * @param totalDebt Total debt value in base currency
     * @return leverage The current leverage (18 decimals)
     */
    function calculateLeverage(
        uint256 totalCollateral,
        uint256 totalDebt
    ) internal pure returns (uint256 leverage) {
        // No debt = 1x leverage
        if (totalDebt == 0) {
            return PRECISION;
        }

        // If debt >= collateral, position is underwater
        if (totalDebt >= totalCollateral) {
            return type(uint256).max; // Indicate invalid/underwater
        }

        // Leverage = Collateral / (Collateral - Debt)
        // For 3x: $3000 collateral, $2000 debt
        // Leverage = 3000 / (3000 - 2000) = 3000 / 1000 = 3x
        leverage = (totalCollateral * PRECISION) / (totalCollateral - totalDebt);
    }

    /**
     * @notice Calculate required flash loan amount for target leverage
     * @dev FlashAmount = (TargetLeverage - 1) * InitialCollateral
     * @param initialCollateral The initial collateral amount
     * @param targetLeverage Target leverage (18 decimals, e.g., 3e18 = 3x)
     * @return flashAmount Amount to flash loan
     */
    function calculateFlashLoanAmount(
        uint256 initialCollateral,
        uint256 targetLeverage
    ) internal pure returns (uint256 flashAmount) {
        require(targetLeverage >= PRECISION, "Target leverage must be >= 1x");
        require(targetLeverage <= MAX_LEVERAGE, "Target leverage exceeds maximum");

        // Flash amount = (targetLeverage - 1) * initialCollateral / PRECISION
        // For 3x with 1 ETH: (3 - 1) * 1 = 2 ETH flash loan
        uint256 multiplier = targetLeverage - PRECISION;
        flashAmount = (initialCollateral * multiplier) / PRECISION;
    }

    /**
     * @notice Calculate safe borrow amount considering LTV
     * @dev SafeBorrow = Collateral * LTV * SafetyBuffer
     * @param collateralValue Collateral value in base currency
     * @param ltv Loan-to-value ratio (basis points, e.g., 8000 = 80%)
     * @param safetyBuffer Safety margin (basis points, e.g., 9500 = 95% of max)
     * @return safeBorrowAmount Safe amount to borrow
     */
    function calculateSafeBorrow(
        uint256 collateralValue,
        uint256 ltv,
        uint256 safetyBuffer
    ) internal pure returns (uint256 safeBorrowAmount) {
        // SafeBorrow = Collateral * (LTV / 10000) * (Buffer / 10000)
        safeBorrowAmount = (collateralValue * ltv * safetyBuffer) / (BPS * BPS);
    }

    /**
     * @notice Calculate how many iterations needed to reach target leverage
     * @dev Approximation based on geometric series
     * @param currentLeverage Current leverage (18 decimals)
     * @param targetLeverage Target leverage (18 decimals)
     * @param ltv Loan-to-value ratio (basis points)
     * @return iterations Estimated number of iterations
     */
    function estimateIterations(
        uint256 currentLeverage,
        uint256 targetLeverage,
        uint256 ltv
    ) internal pure returns (uint256 iterations) {
        if (currentLeverage >= targetLeverage) {
            return 0;
        }

        // Each iteration can increase leverage by approximately LTV factor
        // This is a rough estimate; actual iterations may vary
        uint256 ltvFactor = (ltv * PRECISION) / BPS;
        uint256 leverageRatio = (targetLeverage * PRECISION) / currentLeverage;

        // log(leverageRatio) / log(1 / (1 - LTV))
        // Simplified approximation: iterations ≈ log(ratio) * 2.5
        iterations = 1;
        uint256 accumulated = PRECISION;

        while (accumulated < leverageRatio && iterations < 20) {
            accumulated = (accumulated * PRECISION) / (PRECISION - ltvFactor);
            iterations++;
        }
    }

    /**
     * @notice Calculate safe withdrawal amount during unwind
     * @dev Must maintain health factor above minimum
     * @param totalCollateral Current total collateral
     * @param totalDebt Current total debt
     * @param liquidationThreshold The liquidation threshold (basis points)
     * @param targetHealthFactor Target health factor to maintain (18 decimals)
     * @return safeWithdraw Maximum safe withdrawal amount
     */
    function calculateSafeWithdraw(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 liquidationThreshold,
        uint256 targetHealthFactor
    ) internal pure returns (uint256 safeWithdraw) {
        if (totalDebt == 0) {
            return totalCollateral; // No debt, can withdraw all
        }

        // HealthFactor = (Collateral * LiqThreshold) / Debt
        // To maintain HF >= target:
        // (Collateral - Withdraw) * LiqThreshold >= Debt * TargetHF
        // Withdraw <= Collateral - (Debt * TargetHF) / LiqThreshold

        uint256 minCollateral = (totalDebt * targetHealthFactor * BPS) / (liquidationThreshold * PRECISION);

        if (totalCollateral <= minCollateral) {
            return 0; // Cannot withdraw safely
        }

        safeWithdraw = totalCollateral - minCollateral;
    }

    /**
     * @notice Check if leverage is within acceptable range
     * @param leverage Current leverage (18 decimals)
     * @param targetLeverage Target leverage (18 decimals)
     * @param tolerance Acceptable deviation (basis points, e.g., 100 = 1%)
     * @return withinRange True if within acceptable range
     */
    function isWithinTarget(
        uint256 leverage,
        uint256 targetLeverage,
        uint256 tolerance
    ) internal pure returns (bool withinRange) {
        uint256 deviation;
        if (leverage > targetLeverage) {
            deviation = leverage - targetLeverage;
        } else {
            deviation = targetLeverage - leverage;
        }

        uint256 maxDeviation = (targetLeverage * tolerance) / BPS;
        withinRange = deviation <= maxDeviation;
    }

    /**
     * @notice Validate leverage parameters
     * @param targetLeverage Target leverage to validate
     * @return valid True if parameters are valid
     */
    function validateLeverage(uint256 targetLeverage) internal pure returns (bool valid) {
        valid = targetLeverage >= MIN_LEVERAGE && targetLeverage <= MAX_LEVERAGE;
    }
}
