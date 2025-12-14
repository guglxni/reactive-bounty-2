// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAaveOracle
 * @notice Interface for Aave V3 Price Oracle
 */
interface IAaveOracle {
    /**
     * @notice Returns the asset price in the base currency
     * @param asset The address of the asset
     * @return The price of the asset (with 8 decimals for USD base)
     */
    function getAssetPrice(address asset) external view returns (uint256);

    /**
     * @notice Returns a list of prices from a list of assets addresses
     * @param assets The list of assets addresses
     * @return The prices of the given assets
     */
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);

    /**
     * @notice Returns the address of the source for an asset address
     * @param asset The address of the asset
     * @return The address of the source
     */
    function getSourceOfAsset(address asset) external view returns (address);

    /**
     * @notice Returns the address of the fallback oracle
     * @return The address of the fallback oracle
     */
    function getFallbackOracle() external view returns (address);

    /**
     * @notice Returns the base currency used for the prices (e.g., USD)
     * @return Address of the base currency (address(0) for USD)
     */
    function BASE_CURRENCY() external view returns (address);

    /**
     * @notice Returns the base currency unit (e.g., 1e8 for USD)
     * @return The base currency unit
     */
    function BASE_CURRENCY_UNIT() external view returns (uint256);
}
