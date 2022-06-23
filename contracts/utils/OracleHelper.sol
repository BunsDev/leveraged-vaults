// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

import {IPriceOracle} from "../../interfaces/balancer/IPriceOracle.sol";
import {IBalancerVault} from "../../interfaces/balancer/IBalancerVault.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";
import {BalancerUtils} from "./BalancerUtils.sol";

library OracleHelper {
    /// @notice Gets the time-weighted primary token balance for a given bptAmount
    /// @dev Balancer pool needs to be fully initialized with at least 1024 trades
    /// @param bptAmount BPT amount
    /// @return primaryBalance primary token balance
    function getTimeWeightedPrimaryBalance(
        address pool,
        uint256 oracleWindowInSeconds,
        uint256 primaryindex,
        uint256 primaryWeight,
        uint256 secondaryWeight,
        uint256 primaryDecimals,
        uint256 bptAmount
    ) external view returns (uint256) {
        // Gets the BPT token price
        uint256 bptPrice = BalancerUtils.getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.BPT_PRICE,
            oracleWindowInSeconds
        );

        // The first token in the BPT pool is the primary token.
        // Since bptPrice is always denominated in the first token,
        // Both bptPrice and bptAmount are in 1e18
        // underlyingValue = bptPrice * bptAmount / 1e18
        if (primaryindex == 0) {
            uint256 primaryAmount = (bptPrice * bptAmount) / 1e18;

            // Normalize precision to primary precision
            return (primaryAmount * primaryDecimals) / 1e18;
        }

        // The second token in the BPT pool is the primary token.
        // In this case, we need to convert secondaryTokenValue
        // to underlyingValue using the pairPrice.
        // Both bptPrice and bptAmount are in 1e18
        uint256 secondaryAmount = (bptPrice * bptAmount) / 1e18;

        // Gets the pair price
        uint256 pairPrice = BalancerUtils.getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.PAIR_PRICE,
            oracleWindowInSeconds
        );

        // PairPrice =  (SecondaryAmount / SecondaryWeight) / (PrimaryAmount / PrimaryWeight)
        // (SecondaryAmount / SecondaryWeight) / PairPrice = (PrimaryAmount / PrimaryWeight)
        // PrimaryAmount = (SecondaryAmount / SecondaryWeight) / PairPrice * PrimaryWeight

        // Calculate weighted secondary amount
        secondaryAmount = ((secondaryAmount * 1e18) / secondaryWeight);

        // Calculate primary amount using pair price
        uint256 primaryAmount = ((secondaryAmount * 1e18) / pairPrice);

        // Calculate secondary amount (precision is still 1e18)
        primaryAmount = (primaryAmount * primaryWeight) / 1e18;

        // Normalize precision to secondary precision (Balancer uses 1e18)
        return (primaryAmount * 10**primaryDecimals) / 1e18;
    }

    function getPairPrice(
        address pool,
        address vault,
        bytes32 poolId,
        address tradingModule,
        uint256 oracleWindowInSeconds,
        uint256 balancerOracleWeight
    ) external view returns (uint256) {
        uint256 balancerPrice = BalancerUtils.getTimeWeightedOraclePrice(
            pool,
            IPriceOracle.Variable.PAIR_PRICE,
            oracleWindowInSeconds
        );

        // prettier-ignore
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = IBalancerVault(vault).getPoolTokens(poolId);

        (uint256 chainlinkPrice, uint256 decimals) = ITradingModule(
            tradingModule
        ).getOraclePrice(tokens[1], tokens[0]);

        // Normalize price to 18 decimals
        chainlinkPrice = (chainlinkPrice * 1e18) / decimals;

        return
            (balancerPrice * balancerOracleWeight) /
            1e8 +
            (chainlinkPrice * (1e8 - balancerOracleWeight)) /
            1e8;
    }
}
