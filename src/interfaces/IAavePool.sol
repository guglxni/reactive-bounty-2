// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAavePool
 * @notice Interface for Aave V3 Pool contract
 * @dev Simplified interface with only the functions we need
 */
interface IAavePool {
    /**
     * @notice Supplies an amount of underlying asset into the reserve
     * @param asset The address of the underlying asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that will receive the aTokens
     * @param referralCode Code used to register the integrator (0 for no referral)
     */
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @notice Withdraws an amount of underlying asset from the reserve
     * @param asset The address of the underlying asset to withdraw
     * @param amount The amount to be withdrawn (use type(uint256).max for full balance)
     * @param to The address that will receive the underlying
     * @return The final amount withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    /**
     * @notice Allows users to borrow a specific amount of the reserve underlying asset
     * @param asset The address of the underlying asset to borrow
     * @param amount The amount to be borrowed
     * @param interestRateMode The interest rate mode: 1 for Stable, 2 for Variable
     * @param referralCode Code used to register the integrator (0 for no referral)
     * @param onBehalfOf Address of the user who will receive the debt
     */
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    /**
     * @notice Repays a borrowed amount on a specific reserve
     * @param asset The address of the borrowed underlying asset
     * @param amount The amount to repay (use type(uint256).max to repay full debt)
     * @param interestRateMode The interest rate mode: 1 for Stable, 2 for Variable
     * @param onBehalfOf The address of the user who will get debt reduced
     * @return The final amount repaid
     */
    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external returns (uint256);

    /**
     * @notice Returns the user account data across all reserves
     * @param user The address of the user
     * @return totalCollateralBase The total collateral of the user in base currency
     * @return totalDebtBase The total debt of the user in base currency
     * @return availableBorrowsBase The borrowing power left of the user in base currency
     * @return currentLiquidationThreshold The liquidation threshold of the user
     * @return ltv The loan to value of the user
     * @return healthFactor The current health factor of the user
     */
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    /**
     * @notice Allows smartcontracts to access the liquidity of the pool within one transaction
     * @param receiverAddress The address of the contract receiving the funds
     * @param assets The addresses of the assets being flash-borrowed
     * @param amounts The amounts of the assets being flash-borrowed
     * @param interestRateModes Types of the debt to open if the flash is not returned
     * @param onBehalfOf The address that will receive the debt in case of not returning
     * @param params Variadic packed params to pass to the receiver as extra information
     * @param referralCode Code used to register the integrator (0 for no referral)
     */
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata interestRateModes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;

    /**
     * @notice Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     */
    function getConfiguration(address asset) external view returns (uint256);

    /**
     * @notice Returns the normalized income of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The reserve's normalized income
     */
    function getReserveNormalizedIncome(address asset) external view returns (uint256);

    /**
     * @notice Returns the normalized variable debt per unit of asset
     * @param asset The address of the underlying asset of the reserve
     * @return The reserve normalized variable debt
     */
    function getReserveNormalizedVariableDebt(address asset) external view returns (uint256);

    /**
     * @notice Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     */
    function getReserveData(address asset)
        external
        view
        returns (
            uint256 configuration,
            uint128 liquidityIndex,
            uint128 currentLiquidityRate,
            uint128 variableBorrowIndex,
            uint128 currentVariableBorrowRate,
            uint128 currentStableBorrowRate,
            uint40 lastUpdateTimestamp,
            uint16 id,
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress,
            address interestRateStrategyAddress,
            uint128 accruedToTreasury,
            uint128 unbacked,
            uint128 isolationModeTotalDebt
        );

    /**
     * @notice Allows a borrower to change debt between stable and variable
     * @param asset The address of the underlying asset borrowed
     * @param interestRateMode The current interest rate mode
     */
    function swapBorrowRateMode(address asset, uint256 interestRateMode) external;

    /**
     * @notice Sets the user's eMode category
     * @param categoryId The id of the category
     */
    function setUserEMode(uint8 categoryId) external;

    /**
     * @notice Returns the user's eMode category
     * @param user The address of the user
     * @return The id of the user's eMode category
     */
    function getUserEMode(address user) external view returns (uint256);

    /**
     * @notice Allows to enable/disable a specific asset as collateral
     * @param asset The address of the underlying asset
     * @param useAsCollateral true if the user wants to use the asset as collateral
     */
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;
}
