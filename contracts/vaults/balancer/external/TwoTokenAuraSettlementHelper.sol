// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    TwoTokenAuraSettlementContext, 
    StrategyContext,
    SettlementState,
    RedeemParams,
    StrategyVaultSettings,
    StrategyVaultState
} from "../BalancerVaultTypes.sol";
import {TwoTokenAuraSettlementUtils} from "../internal/TwoTokenAuraSettlementUtils.sol";
import {SettlementUtils} from "../internal/SettlementUtils.sol";
import {StrategyUtils} from "../internal/StrategyUtils.sol";
import {TwoTokenAuraStrategyUtils} from "../internal/TwoTokenAuraStrategyUtils.sol";
import {VaultUtils} from "../internal/VaultUtils.sol";

library TwoTokenAuraSettlementHelper {
    using TwoTokenAuraSettlementUtils for TwoTokenAuraSettlementContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using StrategyUtils for StrategyContext;
    using SettlementUtils for StrategyContext;
    using VaultUtils for StrategyVaultSettings;
    using VaultUtils for StrategyVaultState;

    function settleVaultNormal(
        TwoTokenAuraSettlementContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        SettlementState memory state = SettlementUtils._validateTokensToRedeem(maturity, strategyTokensToRedeem);
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.strategyContext.vaultState.lastSettlementTimestamp,
            context.strategyContext.vaultSettings.settlementCoolDownInMinutes,
            context.strategyContext.vaultSettings.settlementSlippageLimitPercent,
            data
        );

        context._executeNormalSettlement({
            state: state,
            maturity: maturity,
            strategyTokensToRedeem: strategyTokensToRedeem,
            params: params
        });

        context.strategyContext.vaultState.lastSettlementTimestamp = uint32(block.timestamp);
        context.strategyContext.vaultState._setStrategyVaultState();
    }

    function settleVaultPostMaturity(
        TwoTokenAuraSettlementContext memory context,
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        SettlementState memory state = SettlementUtils._validateTokensToRedeem(maturity, strategyTokensToRedeem);
        RedeemParams memory params = SettlementUtils._decodeParamsAndValidate(
            context.strategyContext.vaultState.lastPostMaturitySettlementTimestamp,
            context.strategyContext.vaultSettings.postMaturitySettlementCoolDownInMinutes,
            context.strategyContext.vaultSettings.postMaturitySettlementSlippageLimitPercent,
            data
        );

        context._executeNormalSettlement({
            state: state,
            maturity: maturity,
            strategyTokensToRedeem: strategyTokensToRedeem,
            params: params
        });

        context.strategyContext.vaultState.lastPostMaturitySettlementTimestamp = uint32(block.timestamp);    
        context.strategyContext.vaultState._setStrategyVaultState();  
    }

    function settleVaultEmergency(
        TwoTokenAuraSettlementContext memory context, 
        uint256 maturity, 
        bytes calldata data
    ) external {
        (uint256 bptToSettle, uint256 maxUnderlyingSurplus) = 
            context.strategyContext._getEmergencySettlementParams(
                context.poolContext.basePool, maturity
            );

        uint256 redeemStrategyTokenAmount = context.strategyContext._convertBPTClaimToStrategyTokens(
            bptToSettle, maturity
        );

        int256 expectedUnderlyingRedeemed = context.strategyContext._convertStrategyToUnderlying({
            oracleContext: context.oracleContext,
            poolContext: context.poolContext,
            account: address(this),
            strategyTokenAmount: redeemStrategyTokenAmount,
            maturity: maturity
        });

        SettlementUtils._executeEmergencySettlement({
            maturity: maturity,
            bptToSettle: bptToSettle,
            expectedUnderlyingRedeemed: expectedUnderlyingRedeemed,
            maxUnderlyingSurplus: maxUnderlyingSurplus,
            redeemStrategyTokenAmount: redeemStrategyTokenAmount,
            data: data
        });       
    }
}
