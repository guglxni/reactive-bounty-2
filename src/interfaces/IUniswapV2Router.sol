// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IUniswapV2Router
 * @notice Interface for Uniswap V2 Router
 * @dev Simplified interface with only swap functions we need
 */
interface IUniswapV2Router {
    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible
     * @param amountIn The amount of input tokens to send
     * @param amountOutMin The minimum amount of output tokens that must be received
     * @param path An array of token addresses (path[0] = input, path[n-1] = output)
     * @param to The recipient of the output tokens
     * @param deadline Unix timestamp after which the transaction will revert
     * @return amounts The input token amount and all subsequent output token amounts
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Swaps tokens for exact output tokens
     * @param amountOut The amount of output tokens to receive
     * @param amountInMax The maximum amount of input tokens that can be required
     * @param path An array of token addresses (path[0] = input, path[n-1] = output)
     * @param to The recipient of the output tokens
     * @param deadline Unix timestamp after which the transaction will revert
     * @return amounts The input token amount and all subsequent output token amounts
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Returns the amount of output tokens for a given input
     * @param amountIn The amount of input tokens
     * @param path An array of token addresses
     * @return amounts The amounts of output tokens
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

    /**
     * @notice Returns the amount of input tokens required for a given output
     * @param amountOut The amount of output tokens
     * @param path An array of token addresses
     * @return amounts The amounts of input tokens required
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);

    /**
     * @notice Returns the factory address
     */
    function factory() external view returns (address);

    /**
     * @notice Returns the WETH address
     */
    function WETH() external view returns (address);
}
