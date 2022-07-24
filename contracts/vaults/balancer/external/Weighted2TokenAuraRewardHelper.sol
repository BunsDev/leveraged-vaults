// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    ReinvestRewardParams, 
    Weighted2TokenAuraStrategyContext,
    Weighted2TokenOracleContext
} from "../BalancerVaultTypes.sol";
import {RewardHelper} from "../internal/RewardHelper.sol";
import {BalancerUtils} from "../internal/BalancerUtils.sol";
import {ITradingModule} from "../../../../interfaces/trading/ITradingModule.sol";
import {Weighted2TokenOracleMath} from "../internal/Weighted2TokenOracleMath.sol";

library Weighted2TokenAuraRewardHelper {
    using Weighted2TokenOracleMath for Weighted2TokenOracleContext;

    function reinvestReward(
        Weighted2TokenAuraStrategyContext memory context,
        ReinvestRewardParams memory params
    ) external {
        RewardHelper._reinvestReward(
            params, 
            context.baseContext.tradingModule, 
            context.poolContext,
            context.stakingContext,
            context.oracleContext._getSpotPrice(context.poolContext, 0)
        );
    }
}