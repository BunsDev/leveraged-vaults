// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {
    StrategyContext,
    AuraStakingContext,
    ThreeTokenPoolContext,
    BoostedOracleContext,
    Boosted3TokenAuraStrategyContext,
    StrategyVaultState
} from "../vaults/balancer/BalancerVaultTypes.sol";
import {NotionalUtils} from "../utils/NotionalUtils.sol";
import {Boosted3TokenAuraVaultHelper} from "../vaults/balancer/external/Boosted3TokenAuraVaultHelper.sol";
import {Boosted3TokenAuraStrategyUtils} from "../vaults/balancer/internal/strategy/Boosted3TokenAuraStrategyUtils.sol";
import {Boosted3TokenPoolUtils} from "../vaults/balancer/internal/pool/Boosted3TokenPoolUtils.sol";
import {BalancerUtils} from "../vaults/balancer/internal/pool/BalancerUtils.sol";
import {VaultUtils} from "../vaults/balancer/internal/VaultUtils.sol";
import {ITradingModule} from "../../interfaces/trading/ITradingModule.sol";

contract MockBoosted3TokenAuraVault {
    using Boosted3TokenPoolUtils for ThreeTokenPoolContext;
    using Boosted3TokenAuraStrategyUtils for StrategyContext;

    ThreeTokenPoolContext poolContext;
    BoostedOracleContext oracleContext;
    AuraStakingContext stakingContext;
    ITradingModule tradingModule;

    constructor(Boosted3TokenAuraStrategyContext memory context) {
        poolContext = context.poolContext;
        oracleContext = context.oracleContext;
        stakingContext = context.stakingContext;
        tradingModule = context.baseStrategy.tradingModule;
        poolContext._approveBalancerTokens(address(stakingContext.auraBooster));
    }

    function _deposit(uint256 deposit, uint256 maturity, uint256 minBPT) 
        external returns (uint256 bptMinted) {
        return getStrategyContext().baseStrategy._deposit(
            stakingContext, poolContext, deposit, maturity, minBPT
        );
    }

    function _redeem(uint256 strategyTokens, uint256 maturity, uint256 minPrimary) 
        external returns (uint256 finalPrimaryBalance) {
        return getStrategyContext().baseStrategy._redeem(
            stakingContext, poolContext, strategyTokens, maturity, minPrimary
        );
    }

    function getStrategyContext() public view returns (Boosted3TokenAuraStrategyContext memory) {
        return Boosted3TokenAuraStrategyContext({
            poolContext: poolContext,
            oracleContext: oracleContext,
            stakingContext: stakingContext,
            baseStrategy: StrategyContext({
                totalBPTHeld: _bptHeld(),
                secondaryBorrowCurrencyId: 0, // This strategy does not support secondary borrow
                tradingModule: tradingModule,
                vaultSettings: VaultUtils._getStrategyVaultSettings(),
                vaultState: VaultUtils._getStrategyVaultState()
            })
        });
    }

    function convertStrategyToUnderlying(
        address account, 
        uint256 strategyTokenAmount, 
        uint256 maturity
    ) public view returns (int256 underlyingValue) {
        Boosted3TokenAuraStrategyContext memory context = getStrategyContext();
        return context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext,
            poolContext: context.poolContext,
            account: account,
            maturity: maturity,
            strategyTokenAmount: strategyTokenAmount   
        });
    }

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return stakingContext.auraRewardPool.balanceOf(address(this));
    }

    receive() external payable {}
}
