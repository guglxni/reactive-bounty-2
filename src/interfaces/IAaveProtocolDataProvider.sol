// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAaveProtocolDataProvider
 * @notice Interface for Aave V3 Protocol Data Provider
 * @dev Provides detailed data about reserves and user positions
 */
interface IAaveProtocolDataProvider {
    /**
     * @notice Returns the user data for a specific reserve
     * @param asset The address of the underlying asset
     * @param user The address of the user
     * @return currentATokenBalance The current aToken balance of the user
     * @return currentStableDebt The current stable debt of the user
     * @return currentVariableDebt The current variable debt of the user
     * @return principalStableDebt The principal stable debt of the user
     * @return scaledVariableDebt The scaled variable debt of the user
     * @return stableBorrowRate The stable borrow rate of the user
     * @return liquidityRate The liquidity rate
     * @return stableRateLastUpdated The timestamp of the last stable rate update
     * @return usageAsCollateralEnabled True if the user is using the asset as collateral
     */
    function getUserReserveData(address asset, address user)
        external
        view
        returns (
            uint256 currentATokenBalance,
            uint256 currentStableDebt,
            uint256 currentVariableDebt,
            uint256 principalStableDebt,
            uint256 scaledVariableDebt,
            uint256 stableBorrowRate,
            uint256 liquidityRate,
            uint40 stableRateLastUpdated,
            bool usageAsCollateralEnabled
        );

    /**
     * @notice Returns the configuration data of the reserve
     * @param asset The address of the underlying asset
     * @return decimals The number of decimals of the reserve
     * @return ltv The loan to value of the asset
     * @return liquidationThreshold The liquidation threshold
     * @return liquidationBonus The liquidation bonus
     * @return reserveFactor The reserve factor
     * @return usageAsCollateralEnabled True if usage as collateral is enabled
     * @return borrowingEnabled True if borrowing is enabled
     * @return stableBorrowRateEnabled True if stable rate borrowing is enabled
     * @return isActive True if the reserve is active
     * @return isFrozen True if the reserve is frozen
     */
    function getReserveConfigurationData(address asset)
        external
        view
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        );

    /**
     * @notice Returns the aToken, stable debt token and variable debt token addresses
     * @param asset The address of the underlying asset
     * @return aTokenAddress The aToken address
     * @return stableDebtTokenAddress The stable debt token address
     * @return variableDebtTokenAddress The variable debt token address
     */
    function getReserveTokensAddresses(address asset)
        external
        view
        returns (
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress
        );

    /**
     * @notice Returns the caps parameters of a reserve
     * @param asset The address of the underlying asset
     * @return borrowCap The borrow cap
     * @return supplyCap The supply cap
     */
    function getReserveCaps(address asset) external view returns (uint256 borrowCap, uint256 supplyCap);

    /**
     * @notice Returns the total debt for a given asset
     * @param asset The address of the underlying asset
     * @return The total debt
     */
    function getTotalDebt(address asset) external view returns (uint256);

    /**
     * @notice Returns the efficiency mode category of the asset
     * @param asset The address of the underlying asset
     * @return The category id of the efficiency mode
     */
    function getReserveEModeCategory(address asset) external view returns (uint256);
}
