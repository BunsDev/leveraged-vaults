// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {
    RewardTokenTradeParams,
    ReinvestRewardParams,
    PoolContext,
    OracleContext
} from "./BalancerVaultTypes.sol";
import {Constants} from "../../global/Constants.sol";
import {SafeInt256} from "../../global/SafeInt256.sol";
import {BalancerUtils} from "./BalancerUtils.sol";
import {TokenUtils} from "../../utils/TokenUtils.sol";
import {TradeHandler} from "../../trading/TradeHandler.sol";
import {ITradingModule, Trade} from "../../../interfaces/trading/ITradingModule.sol";
import {ILiquidityGauge} from "../../../interfaces/balancer/ILiquidityGauge.sol";
import {nProxy} from "../../proxy/nProxy.sol";
import {IERC20} from "../../../interfaces/IERC20.sol";

library RewardHelper {
    using TokenUtils for IERC20;
    using TradeHandler for Trade;
    using SafeInt256 for uint256;
    using SafeInt256 for int256;

    error InvalidRewardToken(address token);
    error InvalidMaxAmounts(uint256 oraclePrice, uint256 maxPrimary, uint256 maxSecondary);
    error InvalidSpotPrice(uint256 oraclePrice, uint256 spotPrice);

    event RewardReinvested(address token, uint256 primaryAmount, uint256 secondaryAmount, uint256 bptAmount);

    function _isValidRewardToken(PoolContext memory context, address token)
        private view returns (bool) {
        if (token == address(context.balToken) || token == address(context.auraToken)) return true;
        else {
            if (address(context.liquidityGauge) != address(0)) {
                uint256 rewardTokenCount = context.liquidityGauge.reward_count();
                for (uint256 i; i < rewardTokenCount; i++) {
                    if (context.liquidityGauge.reward_tokens(i) == token) return true;
                }
            }
            return false;
        }
    }

    function _validateTrades(
        PoolContext memory context,
        Trade memory primaryTrade,
        Trade memory secondaryTrade,
        address primaryToken,
        address secondaryToken
    ) private view {
        // Validate trades
        if (!_isValidRewardToken(context, primaryTrade.sellToken)) {
            revert InvalidRewardToken(primaryTrade.sellToken);
        }
        if (primaryTrade.sellToken != secondaryTrade.sellToken) {
            revert InvalidRewardToken(secondaryTrade.sellToken);
        }
        if (primaryTrade.buyToken != primaryToken) {
            revert InvalidRewardToken(primaryTrade.buyToken);
        }
        if (secondaryTrade.buyToken != secondaryToken) {
            revert InvalidRewardToken(secondaryTrade.buyToken);
        }
    }

    function _executeRewardTrades(
        PoolContext memory context,
        ITradingModule tradingModule,
        bytes memory data
    ) private returns (address rewardToken, uint256 primaryAmount, uint256 secondaryAmount) {
        RewardTokenTradeParams memory params = abi.decode(
            data,
            (RewardTokenTradeParams)
        );

        _validateTrades(
            context,
            params.primaryTrade,
            params.secondaryTrade,
            context.primaryToken,
            context.secondaryToken
        );

        (/*uint256 amountSold*/, primaryAmount) = _executeTradeWithDynamicSlippage(
            params.primaryTradeDexId,
            params.primaryTrade,
            tradingModule,
            Constants.REWARD_TRADE_SLIPPAGE_PERCENT
        );

        (
            /*uint256 amountSold*/, secondaryAmount) = _executeTradeWithDynamicSlippage(
            params.secondaryTradeDexId,
            params.secondaryTrade,
            tradingModule,
            Constants.REWARD_TRADE_SLIPPAGE_PERCENT
        );

        rewardToken = params.primaryTrade.sellToken;
    }

    function _executeTradeWithDynamicSlippage(
        uint16 dexId,
        Trade memory trade,
        ITradingModule tradingModule,
        uint32 dynamicSlippageLimit
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        (bool success, bytes memory result) = nProxy(payable(address(tradingModule))).getImplementation()
            .delegatecall(abi.encodeWithSelector(
                ITradingModule.executeTradeWithDynamicSlippage.selector,
                dexId, trade, dynamicSlippageLimit
            )
        );
        require(success);
        (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
    }

    function claimRewardTokens(PoolContext memory context, uint16 feePercentage, address feeReceiver) external {
        uint256 balBefore = context.balToken.balanceOf(address(this));
        context.auraRewardPool.getReward(address(this), true);
        uint256 balClaimed = context.balToken.balanceOf(address(this)) - balBefore;

        if (balClaimed > 0 && feePercentage != 0 && feeReceiver != address(0)) {
            uint256 feeAmount = balClaimed * feePercentage / Constants.VAULT_PERCENT_BASIS;
            context.balToken.checkTransfer(feeReceiver, feeAmount);
        }
    }

    function _validateJoinAmounts(
        OracleContext memory context, 
        ITradingModule tradingModule,
        uint256 primaryAmount, 
        uint256 secondaryAmount
    ) private view {
        (uint256 normalizedPrimary, uint256 normalizedSecondary) = BalancerUtils._normalizeBalances(
            primaryAmount, context.primaryDecimals, secondaryAmount, context.secondaryDecimals
        );
        (
            int256 answer, int256 decimals
        ) = tradingModule.getOraclePrice(context.poolContext.secondaryToken, context.poolContext.primaryToken);

        require(decimals == BalancerUtils.BALANCER_PRECISION.toInt());

        uint256 oraclePrice = answer.toUint();
        uint256 lowerLimit = (oraclePrice * Constants.MAX_JOIN_AMOUNTS_LOWER_LIMIT) / 100;
        uint256 upperLimit = (oraclePrice * Constants.MAX_JOIN_AMOUNTS_UPPER_LIMIT) / 100;

        // Check spot price against oracle price to make sure it hasn't been manipulated
        uint256 spotPrice = BalancerUtils.getSpotPrice(context, 0);
        if (spotPrice < lowerLimit || upperLimit < spotPrice) {
            revert InvalidSpotPrice(oraclePrice, spotPrice);
        }

        // Check join amounts against oracle price to minimize BPT slippage
        uint256 calculatedPairPrice = normalizedPrimary * BalancerUtils.BALANCER_PRECISION / 
            normalizedSecondary;
        if (calculatedPairPrice < lowerLimit || upperLimit < calculatedPairPrice) {
            revert InvalidMaxAmounts(oraclePrice, primaryAmount, secondaryAmount);
        }
    }

    function reinvestReward(
        ReinvestRewardParams memory params,
        ITradingModule tradingModule,
        OracleContext memory context
    ) external {
        (address rewardToken, uint256 primaryAmount, uint256 secondaryAmount) = _executeRewardTrades(
            context.poolContext,
            tradingModule,
            params.tradeData
        );

        // Make sure we are joining with the right proportion to minimize slippage
        _validateJoinAmounts(context, tradingModule, primaryAmount, secondaryAmount);
        
        uint256 bptAmount = BalancerUtils.joinPoolExactTokensIn(
            context.poolContext,
            primaryAmount,
            secondaryAmount,
            params.minBPT
        );

        context.poolContext.auraBooster.deposit(
            context.poolContext.auraPoolId, bptAmount, true // stake = true
        );

        emit RewardReinvested(rewardToken, primaryAmount, secondaryAmount, bptAmount); 
    }
}
