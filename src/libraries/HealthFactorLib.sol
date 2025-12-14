// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title HealthFactorLib
 * @notice Library for health factor calculations and safety checks
 * @dev Health factor calculations match Aave V3's methodology
 */
library HealthFactorLib {
    /// @notice Precision for health factor (18 decimals, same as Aave)
    uint256 constant PRECISION = 1e18;

    /// @notice Basis points denominator
    uint256 constant BPS = 10000;

    /// @notice Default minimum safe health factor (1.1 = 1.1e18)
    uint256 constant DEFAULT_MIN_HEALTH_FACTOR = 1.1e18;

    /// @notice Critical health factor threshold (1.05 = 1.05e18)
    uint256 constant CRITICAL_HEALTH_FACTOR = 1.05e18;

    /// @notice Liquidation threshold (1.0 = 1e18)
    uint256 constant LIQUIDATION_THRESHOLD = 1e18;

    /**
     * @notice Calculate health factor from Aave data
     * @dev HealthFactor = (Collateral * LiquidationThreshold) / TotalDebt
     * @param totalCollateral Total collateral value in base currency (8 decimals from Aave)
     * @param totalDebt Total debt value in base currency (8 decimals from Aave)
     * @param avgLiquidationThreshold Weighted average liquidation threshold (4 decimals, e.g., 8500 = 85%)
     * @return healthFactor The calculated health factor (18 decimals)
     */
    function calculateHealthFactor(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 avgLiquidationThreshold
    ) internal pure returns (uint256 healthFactor) {
        if (totalDebt == 0) {
            return type(uint256).max; // No debt = infinite health
        }

        // HF = (Collateral * LiqThreshold) / Debt
        // LiqThreshold is in basis points (e.g., 8500 = 85%)
        // Result in 18 decimals
        healthFactor = (totalCollateral * avgLiquidationThreshold * PRECISION) / (totalDebt * BPS);
    }

    /**
     * @notice Check if health factor is safe
     * @param healthFactor Current health factor (18 decimals)
     * @param minHealthFactor Minimum acceptable health factor (18 decimals)
     * @return isSafe True if health factor is above minimum
     */
    function isSafe(uint256 healthFactor, uint256 minHealthFactor) internal pure returns (bool) {
        return healthFactor >= minHealthFactor;
    }

    /**
     * @notice Check if position is in critical state
     * @param healthFactor Current health factor (18 decimals)
     * @return isCritical True if health factor is below critical threshold
     */
    function isCritical(uint256 healthFactor) internal pure returns (bool) {
        return healthFactor < CRITICAL_HEALTH_FACTOR;
    }

    /**
     * @notice Check if position can be liquidated
     * @param healthFactor Current health factor (18 decimals)
     * @return canLiquidate True if health factor is below 1.0
     */
    function canBeLiquidated(uint256 healthFactor) internal pure returns (bool) {
        return healthFactor < LIQUIDATION_THRESHOLD;
    }

    /**
     * @notice Determine the urgency level of a position
     * @param healthFactor Current health factor (18 decimals)
     * @return level 0 = Safe, 1 = Warning, 2 = Critical, 3 = Liquidatable
     */
    function getUrgencyLevel(uint256 healthFactor) internal pure returns (uint8 level) {
        if (healthFactor >= DEFAULT_MIN_HEALTH_FACTOR) {
            return 0; // Safe
        } else if (healthFactor >= CRITICAL_HEALTH_FACTOR) {
            return 1; // Warning
        } else if (healthFactor >= LIQUIDATION_THRESHOLD) {
            return 2; // Critical
        } else {
            return 3; // Liquidatable
        }
    }

    /**
     * @notice Calculate how much to repay to restore target health factor
     * @param totalCollateral Current collateral value
     * @param totalDebt Current debt value
     * @param liquidationThreshold The liquidation threshold (basis points)
     * @param targetHealthFactor Target health factor to achieve (18 decimals)
     * @return repayAmount Amount of debt to repay
     */
    function calculateRepayToRestore(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 liquidationThreshold,
        uint256 targetHealthFactor
    ) internal pure returns (uint256 repayAmount) {
        if (totalDebt == 0) {
            return 0;
        }

        // Current HF = (Collateral * LiqThreshold) / Debt
        // Target HF = (Collateral * LiqThreshold) / (Debt - Repay)
        // Solving for Repay:
        // Repay = Debt - (Collateral * LiqThreshold) / TargetHF

        uint256 targetDebt = (totalCollateral * liquidationThreshold * PRECISION) / (targetHealthFactor * BPS);

        if (totalDebt <= targetDebt) {
            return 0; // Already at or above target
        }

        repayAmount = totalDebt - targetDebt;
    }

    /**
     * @notice Calculate maximum additional borrow while maintaining health factor
     * @param totalCollateral Current collateral value
     * @param totalDebt Current debt value
     * @param liquidationThreshold The liquidation threshold (basis points)
     * @param targetHealthFactor Target health factor to maintain (18 decimals)
     * @return maxBorrow Maximum additional amount that can be borrowed
     */
    function calculateMaxBorrow(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 liquidationThreshold,
        uint256 targetHealthFactor
    ) internal pure returns (uint256 maxBorrow) {
        // Max total debt at target HF:
        // TargetHF = (Collateral * LiqThreshold) / MaxDebt
        // MaxDebt = (Collateral * LiqThreshold) / TargetHF

        uint256 maxTotalDebt = (totalCollateral * liquidationThreshold * PRECISION) / (targetHealthFactor * BPS);

        if (maxTotalDebt <= totalDebt) {
            return 0; // Cannot borrow more
        }

        maxBorrow = maxTotalDebt - totalDebt;
    }

    /**
     * @notice Calculate health factor after a hypothetical borrow
     * @param totalCollateral Current collateral value
     * @param totalDebt Current debt value
     * @param borrowAmount Amount to borrow
     * @param liquidationThreshold The liquidation threshold (basis points)
     * @return newHealthFactor The health factor after borrowing
     */
    function calculateHealthFactorAfterBorrow(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 borrowAmount,
        uint256 liquidationThreshold
    ) internal pure returns (uint256 newHealthFactor) {
        uint256 newDebt = totalDebt + borrowAmount;
        return calculateHealthFactor(totalCollateral, newDebt, liquidationThreshold);
    }

    /**
     * @notice Calculate health factor after a hypothetical supply
     * @param totalCollateral Current collateral value
     * @param totalDebt Current debt value
     * @param supplyAmount Amount to supply (in base currency value)
     * @param liquidationThreshold The liquidation threshold (basis points)
     * @return newHealthFactor The health factor after supplying
     */
    function calculateHealthFactorAfterSupply(
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 supplyAmount,
        uint256 liquidationThreshold
    ) internal pure returns (uint256 newHealthFactor) {
        uint256 newCollateral = totalCollateral + supplyAmount;
        return calculateHealthFactor(newCollateral, totalDebt, liquidationThreshold);
    }

    /**
     * @notice Calculate the buffer above liquidation threshold
     * @param healthFactor Current health factor (18 decimals)
     * @return buffer The buffer as a percentage (basis points)
     */
    function getHealthFactorBuffer(uint256 healthFactor) internal pure returns (uint256 buffer) {
        if (healthFactor <= LIQUIDATION_THRESHOLD) {
            return 0;
        }
        // Buffer = (HF - 1) * 10000 (in basis points)
        buffer = ((healthFactor - LIQUIDATION_THRESHOLD) * BPS) / PRECISION;
    }
}
