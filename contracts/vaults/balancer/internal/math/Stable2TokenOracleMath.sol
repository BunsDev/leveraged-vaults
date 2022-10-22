// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StableOracleContext, TwoTokenPoolContext, StrategyContext} from "../../BalancerVaultTypes.sol";
import {BalancerConstants} from "../BalancerConstants.sol";
import {Errors} from "../../../../global/Errors.sol";
import {TypeConvert} from "../../../../global/TypeConvert.sol";
import {StableMath} from "./StableMath.sol";
import {ITradingModule} from "../../../../../interfaces/trading/ITradingModule.sol";

library Stable2TokenOracleMath {
    using TypeConvert for int256;
    using Stable2TokenOracleMath for StableOracleContext;

    function _getSpotPrice(
        StableOracleContext memory oracleContext, 
        TwoTokenPoolContext memory poolContext, 
        uint256 tokenIndex
    ) internal view returns (uint256 spotPrice) {
        require(tokenIndex < 2); /// @dev invalid token index

        /// Apply scale factors
        uint256 scaledPrimaryBalance = poolContext.primaryBalance * poolContext.primaryScaleFactor 
            / BalancerConstants.BALANCER_PRECISION;
        uint256 scaledSecondaryBalance = poolContext.secondaryBalance * poolContext.secondaryScaleFactor 
            / BalancerConstants.BALANCER_PRECISION;

        /// @notice poolContext balances are always in BALANCER_PRECISION (1e18)
        (uint256 balanceX, uint256 balanceY) = tokenIndex == 0 ?
            (scaledPrimaryBalance, scaledSecondaryBalance) :
            (scaledSecondaryBalance, scaledPrimaryBalance);

        uint256 invariant = StableMath._calculateInvariant(
            oracleContext.ampParam, StableMath._balances(balanceX, balanceY), true // round up
        );

        spotPrice = StableMath._calcSpotPrice({
            amplificationParameter: oracleContext.ampParam,
            invariant: invariant,
            balanceX: balanceX,
            balanceY: balanceY
        });

        /// Apply secondary scale factor in reverse
        uint256 scaleFactor = tokenIndex == 0 ? poolContext.primaryScaleFactor : poolContext.secondaryScaleFactor;
        spotPrice = spotPrice * BalancerConstants.BALANCER_PRECISION / scaleFactor;
    }

    function _checkPriceLimit(
        StrategyContext memory strategyContext,
        uint256 oraclePrice,
        uint256 poolPrice
    ) internal view {
        uint256 lowerLimit = (oraclePrice * 
            (BalancerConstants.VAULT_PERCENT_BASIS - strategyContext.vaultSettings.oraclePriceDeviationLimitPercent)) / 
            BalancerConstants.VAULT_PERCENT_BASIS;
        uint256 upperLimit = (oraclePrice * 
            (BalancerConstants.VAULT_PERCENT_BASIS + strategyContext.vaultSettings.oraclePriceDeviationLimitPercent)) / 
            BalancerConstants.VAULT_PERCENT_BASIS;

        if (poolPrice < lowerLimit || upperLimit < poolPrice) {
            revert Errors.InvalidPrice(oraclePrice, poolPrice);
        }
    }

    /// @notice calculates the expected min exit amounts for a given BPT amount
    function _getMinExitAmounts(
        StableOracleContext calldata oracleContext,
        TwoTokenPoolContext calldata poolContext,
        StrategyContext calldata strategyContext,
        uint256 oraclePrice,
        uint256 bptAmount
    ) internal view returns (uint256 minPrimary, uint256 minSecondary) {
        // Oracle price is always specified in terms of primary, so tokenIndex == 0 for primary
        // Validate the spot price to make sure the pool is not being manipulated
        uint256 spotPrice = _getSpotPrice(oracleContext, poolContext, 0);
        _checkPriceLimit(strategyContext, oraclePrice, spotPrice);

        // min amounts are calculated based on the share of the Balancer pool with a small discount applied
        uint256 totalBPTSupply = poolContext.basePool.pool.totalSupply();
        minPrimary = (poolContext.primaryBalance * bptAmount * 
            strategyContext.vaultSettings.balancerPoolSlippageLimitPercent) / 
            (totalBPTSupply * uint256(BalancerConstants.VAULT_PERCENT_BASIS));
        minSecondary = (poolContext.secondaryBalance * bptAmount * 
            strategyContext.vaultSettings.balancerPoolSlippageLimitPercent) / 
            (totalBPTSupply * uint256(BalancerConstants.VAULT_PERCENT_BASIS));
    }

    function _validateSpotPriceAndPairPrice(
        StableOracleContext calldata oracleContext,
        TwoTokenPoolContext calldata poolContext,
        StrategyContext calldata strategyContext,
        uint256 oraclePrice,
        uint256 primaryAmount, 
        uint256 secondaryAmount
    ) internal view {
        // Oracle price is always specified in terms of primary, so tokenIndex == 0 for primary
        uint256 spotPrice = _getSpotPrice(oracleContext, poolContext, 0);
        _checkPriceLimit(strategyContext, oraclePrice, spotPrice);

        // We always validate in terms of the primary here so it is the first value in the _balances array
        uint256 invariant = StableMath._calculateInvariant(
            oracleContext.ampParam, StableMath._balances(primaryAmount, secondaryAmount), true // round up
        );

        /// @notice Balancer math functions expect all amounts to be in BALANCER_PRECISION
        uint256 primaryPrecision = 10 ** poolContext.primaryDecimals;
        uint256 secondaryPrecision = 10 ** poolContext.secondaryDecimals;
        primaryAmount = primaryAmount * BalancerConstants.BALANCER_PRECISION / primaryPrecision;
        secondaryAmount = secondaryAmount * BalancerConstants.BALANCER_PRECISION / secondaryPrecision;

        uint256 calculatedPairPrice = StableMath._calcSpotPrice({
            amplificationParameter: oracleContext.ampParam,
            invariant: invariant,
            balanceX: primaryAmount,
            balanceY: secondaryAmount
        });

        _checkPriceLimit(strategyContext, oraclePrice, calculatedPairPrice);
    }
}
