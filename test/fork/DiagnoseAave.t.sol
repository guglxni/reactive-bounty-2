// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPoolDataProvider {
    function getReserveData(address asset) external view returns (
        uint256 unbacked,
        uint256 accruedToTreasuryScaled,
        uint256 totalAToken,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 stableBorrowRate,
        uint256 averageStableBorrowDuration,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex,
        uint40 lastUpdateTimestamp
    );
    
    function getReserveConfigurationData(address asset) external view returns (
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
    
    function getReserveTokensAddresses(address asset) external view returns (
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress
    );
}

interface IAaveOracle {
    function getAssetPrice(address asset) external view returns (uint256);
    function BASE_CURRENCY_UNIT() external view returns (uint256);
}

/**
 * @title DiagnoseAave
 * @notice Diagnostic tests to understand Aave Sepolia state
 */
contract DiagnoseAaveTest is Test {
    // Sepolia addresses
    address constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address constant AAVE_ORACLE = 0x2da88497588bf89281816106C7259e31AF45a663;
    address constant AAVE_DATA_PROVIDER = 0x3e9708d80f7B3e43118013075F7e95CE3AB31F31;
    
    address constant WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    
    IPoolDataProvider dataProvider = IPoolDataProvider(AAVE_DATA_PROVIDER);
    IAaveOracle oracle = IAaveOracle(AAVE_ORACLE);
    
    modifier onlyFork() {
        if (block.chainid != 11155111) {
            console.log("Skipping - not on Sepolia fork");
            return;
        }
        _;
    }
    
    function test_diagnoseUSDCReserve() public onlyFork {
        console.log("\n=== USDC Reserve Diagnosis ===\n");
        
        // Get reserve data
        (
            uint256 unbacked,
            uint256 accruedToTreasuryScaled,
            uint256 totalAToken,
            uint256 totalStableDebt,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 stableBorrowRate,
            ,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            
        ) = dataProvider.getReserveData(USDC);
        
        console.log("totalAToken:", totalAToken);
        console.log("totalStableDebt:", totalStableDebt);
        console.log("totalVariableDebt:", totalVariableDebt);
        console.log("unbacked:", unbacked);
        console.log("liquidityRate (ray):", liquidityRate);
        console.log("variableBorrowRate (ray):", variableBorrowRate);
        console.log("liquidityIndex (ray):", liquidityIndex);
        console.log("variableBorrowIndex (ray):", variableBorrowIndex);
        
        // Get token addresses
        (address aToken, , ) = dataProvider.getReserveTokensAddresses(USDC);
        console.log("\naToken address:", aToken);
        
        // Get actual USDC balance in aToken contract
        uint256 usdcBalance = IERC20(USDC).balanceOf(aToken);
        console.log("Actual USDC in aToken:", usdcBalance);
        
        // Calculate available liquidity
        console.log("\n=== Liquidity Analysis ===");
        console.log("Available liquidity (totalAToken - totalDebt):", 
            totalAToken > (totalStableDebt + totalVariableDebt) 
            ? totalAToken - totalStableDebt - totalVariableDebt 
            : 0);
        
        // Get oracle price
        uint256 usdcPrice = oracle.getAssetPrice(USDC);
        uint256 baseCurrencyUnit = oracle.BASE_CURRENCY_UNIT();
        console.log("\n=== Oracle Info ===");
        console.log("USDC price:", usdcPrice);
        console.log("Base currency unit:", baseCurrencyUnit);
        
        // Get decimals
        (uint256 decimals, , , , , , , , , ) = dataProvider.getReserveConfigurationData(USDC);
        console.log("USDC decimals:", decimals);
        
        // Test conversion
        console.log("\n=== Conversion Test ===");
        uint256 testBaseCurrencyAmount = 100 * 1e8; // $100 in 8 decimals
        uint256 tokenAmount = (testBaseCurrencyAmount * (10 ** decimals)) / usdcPrice;
        console.log("$100 (base currency) converts to:", tokenAmount, "USDC raw units");
        console.log("Which is:", tokenAmount / (10 ** decimals), "USDC");
    }
    
    function test_diagnoseWETHReserve() public onlyFork {
        console.log("\n=== WETH Reserve Diagnosis ===\n");
        
        // Get reserve data
        (
            uint256 unbacked,
            ,
            uint256 totalAToken,
            uint256 totalStableDebt,
            uint256 totalVariableDebt,
            ,
            ,
            ,
            ,
            ,
            ,
            
        ) = dataProvider.getReserveData(WETH);
        
        console.log("totalAToken:", totalAToken);
        console.log("totalStableDebt:", totalStableDebt);
        console.log("totalVariableDebt:", totalVariableDebt);
        console.log("unbacked:", unbacked);
        
        // Get token addresses
        (address aToken, , ) = dataProvider.getReserveTokensAddresses(WETH);
        uint256 wethBalance = IERC20(WETH).balanceOf(aToken);
        console.log("\nActual WETH in aToken:", wethBalance);
        
        // Get oracle price
        uint256 wethPrice = oracle.getAssetPrice(WETH);
        console.log("WETH price:", wethPrice);
        
        (uint256 decimals, , , , , , , , , ) = dataProvider.getReserveConfigurationData(WETH);
        console.log("WETH decimals:", decimals);
    }
    
    function test_diagnoseWadRayOverflow() public onlyFork {
        console.log("\n=== WadRay Overflow Analysis ===\n");
        
        // Get USDC variable debt  
        (
            ,
            ,
            ,
            ,
            uint256 totalVariableDebt,
            ,
            ,
            ,
            ,
            ,
            uint256 variableBorrowIndex,
            
        ) = dataProvider.getReserveData(USDC);
        
        console.log("totalVariableDebt:", totalVariableDebt);
        console.log("variableBorrowIndex:", variableBorrowIndex);
        
        // Simulate wadToRay calculation
        // wadToRay multiplies by 1e9
        uint256 WAD_RAY_RATIO = 1e9;
        
        console.log("\n=== WadToRay Simulation ===");
        console.log("Input (totalVariableDebt):", totalVariableDebt);
        
        // Check if this would overflow
        uint256 maxSafe = type(uint256).max / WAD_RAY_RATIO;
        console.log("Max safe input for wadToRay:", maxSafe);
        
        if (totalVariableDebt > maxSafe) {
            console.log("!!! OVERFLOW WOULD OCCUR !!!");
            console.log("Debt is", totalVariableDebt / maxSafe, "times too large");
        } else {
            uint256 result = totalVariableDebt * WAD_RAY_RATIO;
            console.log("wadToRay result:", result);
        }
        
        // USDC uses 6 decimals but Aave expects WAD (18 decimals) for debt calculations
        // So internally, scaled debt should already be normalized somehow
        // Let me check if totalVariableDebt is in scaled or actual units
        
        console.log("\n=== Debt Analysis ===");
        console.log("If debt is in USDC units (6 decimals):", totalVariableDebt / 1e6, "USDC");
        console.log("If debt is in WAD units (18 decimals):", totalVariableDebt / 1e18, "USDC");
        console.log("If debt is in RAY units (27 decimals):", totalVariableDebt / 1e27, "USDC");
    }
}
