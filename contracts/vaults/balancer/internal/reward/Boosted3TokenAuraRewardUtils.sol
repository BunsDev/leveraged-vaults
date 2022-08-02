// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    SingleSidedRewardTradeParams,
    ReinvestRewardParams,
    ThreeTokenPoolContext,
    AuraStakingContext,
    BoostedOracleContext
} from "../../BalancerVaultTypes.sol";
import {Events} from "../../../../global/Events.sol";
import {Errors} from "../../../../global/Errors.sol";
import {Constants} from "../../../../global/Constants.sol";
import {TradeHandler} from "../../../../trading/TradeHandler.sol";
import {Boosted3TokenPoolUtils} from "../pool/Boosted3TokenPoolUtils.sol";
import {AuraStakingUtils} from "../staking/AuraStakingUtils.sol";
import {StableMath} from "../math/StableMath.sol";
import {ITradingModule, Trade} from "../../../../../interfaces/trading/ITradingModule.sol";

library Boosted3TokenAuraRewardUtils {
    using TradeHandler for Trade;
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using AuraStakingUtils for AuraStakingContext;

    function _validateTrades(
        AuraStakingContext memory context,
        Trade memory trade,
        address primaryToken
    ) private pure {
        // Validate trades
        if (!context._isValidRewardToken(trade.sellToken)) {
            revert Errors.InvalidRewardToken(trade.sellToken);
        }
        if (trade.buyToken != primaryToken) {
            revert Errors.InvalidRewardToken(trade.buyToken);
        }
    }

    function _executeRewardTrades(
        ThreeTokenPoolContext memory poolContext,
        AuraStakingContext memory stakingContext,
        ITradingModule tradingModule,
        bytes memory data
    ) private returns (address rewardToken, uint256 primaryAmount) {
        SingleSidedRewardTradeParams memory params = abi.decode(
            data,
            (SingleSidedRewardTradeParams)
        );

        _validateTrades(
            stakingContext,
            params.trade,
            poolContext.basePool.primaryToken
        );

        (/*uint256 amountSold*/, primaryAmount) = params.trade._executeTradeWithDynamicSlippage(
            params.dexId, tradingModule, Constants.REWARD_TRADE_SLIPPAGE_PERCENT
        );

        rewardToken = params.trade.sellToken;
    }

    function _reinvestReward(
        ThreeTokenPoolContext memory poolContext,
        BoostedOracleContext memory oracleContext,
        AuraStakingContext memory stakingContext,
        ITradingModule tradingModule,
        ReinvestRewardParams memory params
    ) internal {
        (address rewardToken, uint256 primaryAmount) = _executeRewardTrades(
            poolContext,
            stakingContext,
            tradingModule,
            params.tradeData
        );

        // Calculate minBPT to minimize slippage
        (
           uint256 virtualSupply, 
           uint256[] memory balances, 
           uint256 invariant
        ) = poolContext._getValidatedPoolData(
            oracleContext, tradingModule
        );

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[0] = primaryAmount;

        uint256 minBPT = StableMath._calcBptOutGivenExactTokensIn({
            amp: oracleContext.ampParam,
            balances: balances,
            amountsIn: amountsIn,
            bptTotalSupply: virtualSupply,
            swapFeePercentage: 0,
            currentInvariant: invariant
        });

        // TODO: make this nicer, reduce minBPT by 5%
        minBPT = minBPT * 95 / 100;

        uint256 bptAmount = poolContext._joinPoolExactTokensIn(primaryAmount, minBPT);

        stakingContext.auraBooster.deposit(
            stakingContext.auraPoolId, bptAmount, true // stake = true
        );

        emit Events.RewardReinvested(rewardToken, primaryAmount, 0, bptAmount); 
    }  
}