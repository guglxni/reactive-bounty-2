// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFlashLoanReceiver
 * @notice Interface for Aave V3 Flash Loan Receiver
 * @dev Contracts receiving flash loans must implement this interface
 */
interface IFlashLoanReceiver {
    /**
     * @notice Executes an operation after receiving the flash-borrowed assets
     * @dev Ensure the contract can return the debt + premium
     * @param assets The addresses of the flash-borrowed assets
     * @param amounts The amounts of the flash-borrowed assets
     * @param premiums The fee of each flash-borrowed asset
     * @param initiator The address of the flashloan initiator
     * @param params The byte-encoded params passed when initiating the flashloan
     * @return True if the execution was successful
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);

    /**
     * @notice Returns the address of the Aave Pool
     * @return The address of the Aave Pool
     */
    function POOL() external view returns (address);

    /**
     * @notice Returns the address of the addresses provider
     * @return The address of the Addresses Provider
     */
    function ADDRESSES_PROVIDER() external view returns (address);
}
