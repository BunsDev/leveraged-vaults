// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {BalancerConstants} from "./balancer/internal/BalancerConstants.sol";
import {Errors} from "../global/Errors.sol";
import {
    AuraVaultDeploymentParams,
    InitParams,
    ReinvestRewardParams,
    StrategyVaultSettings,
    StrategyVaultState,
    PoolContext,
    TwoTokenPoolContext,
    StableOracleContext,
    MetaStable2TokenAuraStrategyContext,
    StrategyContext
} from "./balancer/BalancerVaultTypes.sol";
import {BalancerStrategyBase} from "./balancer/BalancerStrategyBase.sol";
import {MetaStable2TokenVaultMixin} from "./balancer/mixins/MetaStable2TokenVaultMixin.sol";
import {AuraStakingMixin} from "./balancer/mixins/AuraStakingMixin.sol";
import {NotionalProxy} from "../../interfaces/notional/NotionalProxy.sol";
import {VaultUtils} from "./balancer/internal/VaultUtils.sol";
import {StrategyUtils} from "./balancer/internal/strategy/StrategyUtils.sol";
import {TwoTokenAuraStrategyUtils} from "./balancer/internal/strategy/TwoTokenAuraStrategyUtils.sol";
import {TwoTokenPoolUtils} from "./balancer/internal/pool/TwoTokenPoolUtils.sol";
import {MetaStable2TokenAuraVaultHelper} from "./balancer/external/MetaStable2TokenAuraVaultHelper.sol";
import {MetaStable2TokenAuraSettlementHelper} from "./balancer/external/MetaStable2TokenAuraSettlementHelper.sol";

contract MetaStable2TokenAuraVault is
    BalancerStrategyBase,
    MetaStable2TokenVaultMixin,
    AuraStakingMixin
{
    using VaultUtils for StrategyVaultSettings;
    using StrategyUtils for StrategyContext;
    using TwoTokenAuraStrategyUtils for StrategyContext;
    using TwoTokenPoolUtils for TwoTokenPoolContext;
    
    constructor(NotionalProxy notional_, AuraVaultDeploymentParams memory params) 
        BalancerStrategyBase(notional_, params.baseParams) 
        MetaStable2TokenVaultMixin(
            params.primaryBorrowCurrencyId,
            params.baseParams.balancerPoolId
        )
        AuraStakingMixin(params.baseParams.liquidityGauge, params.auraRewardPool, params.baseParams.feeReceiver)
    {}

    function strategy() external override view returns (bytes4) {
        return bytes4(keccak256("MetaStable2TokenAura"));
    }

    function initialize(InitParams calldata params)
        external
        initializer
        onlyNotionalOwner
    {
        __INIT_VAULT(params.name, params.borrowCurrencyId);
        VaultUtils.setStrategyVaultSettings(
            params.settings, uint32(MAX_ORACLE_QUERY_WINDOW), BalancerConstants.VAULT_PERCENT_BASIS
        );
        _twoTokenPoolContext()._approveBalancerTokens(address(_auraStakingContext().auraBooster));
    }

    function _depositFromNotional(
        address account,
        uint256 deposit,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 strategyTokensMinted) {
        // Entering the vault is not allowed within the settlement window
        // @audit This is enforced by notional
        _revertInSettlementWindow(maturity);
        strategyTokensMinted = MetaStable2TokenAuraVaultHelper.depositFromNotional(
            _strategyContext(), account, deposit, maturity, data
        );
    }

    function _redeemFromNotional(
        address account,
        uint256 strategyTokens,
        uint256 maturity,
        bytes calldata data
    ) internal override returns (uint256 finalPrimaryBalance) {        
        require(strategyTokens <= type(uint80).max); /// @dev strategyTokens overflow

        // @audit This is ok now that we are not borrowing in secondary
        // Exiting the vault is not allowed within the settlement window
        if (account != address(this)) {
            _revertInSettlementWindow(maturity);            
        }
        finalPrimaryBalance = MetaStable2TokenAuraVaultHelper.redeemFromNotional(
            _strategyContext(), account, strategyTokens, maturity, data
        );
    }

    function convertStrategyToUnderlying(
        address account,
        uint256 strategyTokenAmount,
        uint256 maturity
    ) public view override returns (int256 underlyingValue) {
        MetaStable2TokenAuraStrategyContext memory context = _strategyContext();
        underlyingValue = context.baseStrategy._convertStrategyToUnderlying({
            oracleContext: context.oracleContext.baseOracle,
            poolContext: context.poolContext,
            strategyTokenAmount: strategyTokenAmount
        });
    }

    function settleVaultNormal(
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external {
        if (maturity <= block.timestamp) {
            revert Errors.PostMaturitySettlement();
        }
        if (block.timestamp < maturity - SETTLEMENT_PERIOD_IN_SECONDS) {
            revert Errors.NotInSettlementWindow();
        }
        MetaStable2TokenAuraSettlementHelper.settleVaultNormal(
            _strategyContext(), maturity, strategyTokensToRedeem, data
        );
    }

    function settleVaultPostMaturity(
        uint256 maturity,
        uint256 strategyTokensToRedeem,
        bytes calldata data
    ) external onlyNotionalOwner {
        if (block.timestamp < maturity) {
            revert Errors.HasNotMatured();
        }
        MetaStable2TokenAuraSettlementHelper.settleVaultPostMaturity(
            _strategyContext(), maturity, strategyTokensToRedeem, data
        );
    }

    function settleVaultEmergency(uint256 maturity, bytes calldata data) external {
        // No need for emergency settlement during the settlement window
        _revertInSettlementWindow(maturity);
        MetaStable2TokenAuraSettlementHelper.settleVaultEmergency(
            _strategyContext(), maturity, data
        );
    }

    function reinvestReward(ReinvestRewardParams calldata params) external {
        MetaStable2TokenAuraVaultHelper.reinvestReward(_strategyContext(), params);
    }

    /// @notice Updates the vault settings
    /// @param settings vault settings
    function setStrategyVaultSettings(StrategyVaultSettings calldata settings)
        external
        onlyNotionalOwner
    {
        VaultUtils.setStrategyVaultSettings(
            settings, uint32(MAX_ORACLE_QUERY_WINDOW), BalancerConstants.VAULT_PERCENT_BASIS
        );
    }

    function _strategyContext() private view returns (MetaStable2TokenAuraStrategyContext memory) {
        return MetaStable2TokenAuraStrategyContext({
            poolContext: _twoTokenPoolContext(),
            oracleContext: _stableOracleContext(),
            stakingContext: _auraStakingContext(),
            baseStrategy: StrategyContext({
                totalBPTHeld: _bptHeld(),
                settlementPeriodInSeconds: SETTLEMENT_PERIOD_IN_SECONDS,
                tradingModule: TRADING_MODULE,
                vaultSettings: VaultUtils.getStrategyVaultSettings(),
                vaultState: VaultUtils.getStrategyVaultState(),
                feeReceiver: FEE_RECEIVER
            })
        });
    }
    
    function getStrategyContext() external view returns (MetaStable2TokenAuraStrategyContext memory) {
        return _strategyContext();
    }
    
    // @audit consolidate some of this into the pool mixin
    function convertBPTClaimToStrategyTokens(uint256 bptClaim, uint256 maturity)
        external view returns (uint256 strategyTokenAmount) {
        return _strategyContext().baseStrategy._convertBPTClaimToStrategyTokens(bptClaim);
    }

   /// @notice Converts strategy tokens to BPT
    function convertStrategyTokensToBPTClaim(uint256 strategyTokenAmount, uint256 maturity) 
        external view returns (uint256 bptClaim) {
        return _strategyContext().baseStrategy._convertStrategyTokensToBPTClaim(strategyTokenAmount);
    }

    /// @dev Gets the total BPT held by the aura reward pool
    function _bptHeld() internal view returns (uint256) {
        return AURA_REWARD_POOL.balanceOf(address(this));
    }

}
