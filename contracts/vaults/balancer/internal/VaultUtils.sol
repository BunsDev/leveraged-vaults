// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {StrategyVaultSettings, StrategyVaultState} from "../BalancerVaultTypes.sol";
import {NotionalUtils} from "../../../utils/NotionalUtils.sol";
import {BalancerConstants} from "./BalancerConstants.sol";

library VaultUtils {
    uint256 private constant STRATEGY_VAULT_SETTINGS_SLOT = 1000001;
    uint256 private constant STRATEGY_VAULT_STATE_SLOT    = 1000002;

    function _settings() private pure returns (mapping(uint256 => StrategyVaultSettings) storage store) {
        assembly { store.slot := STRATEGY_VAULT_SETTINGS_SLOT }
    }

    function _state() private pure returns (mapping(uint256 => StrategyVaultState) storage store) {
        assembly { store.slot := STRATEGY_VAULT_STATE_SLOT }
    }

    function getStrategyVaultSettings() internal view returns (StrategyVaultSettings memory) {
        // Hardcode to the zero slot
        return _settings()[0];
    }

    function setStrategyVaultSettings(
        StrategyVaultSettings memory settings, 
        uint32 maxOracleQueryWindow,
        uint16 balancerOracleWeight
    ) internal {
        require(settings.oracleWindowInSeconds <= maxOracleQueryWindow);
        require(settings.settlementCoolDownInMinutes <= BalancerConstants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.postMaturitySettlementCoolDownInMinutes <= BalancerConstants.MAX_SETTLEMENT_COOLDOWN_IN_MINUTES);
        require(settings.balancerOracleWeight <= balancerOracleWeight);
        require(settings.maxBalancerPoolShare <= BalancerConstants.VAULT_PERCENT_BASIS);
        require(settings.settlementSlippageLimitPercent <= BalancerConstants.SLIPPAGE_LIMIT_PRECISION);
        require(settings.postMaturitySettlementSlippageLimitPercent <= BalancerConstants.SLIPPAGE_LIMIT_PRECISION);
        require(settings.feePercentage <= BalancerConstants.VAULT_PERCENT_BASIS);

        mapping(uint256 => StrategyVaultSettings) storage store = _settings();
        // Hardcode to the zero slot
        store[0] = settings;
    }

    function getStrategyVaultState() internal view returns (StrategyVaultState memory) {
        // Hardcode to the zero slot
        return _state()[0];
    }

    function setStrategyVaultState(StrategyVaultState memory state) internal {
        mapping(uint256 => StrategyVaultState) storage store = _state();
        // Hardcode to the zero slot
        store[0] = state;
    }

    // @audit threshold is not checked in all the correct locations
    function _bptThreshold(StrategyVaultSettings memory strategyVaultSettings, uint256 totalBPTSupply) 
        internal pure returns (uint256) {
        return (totalBPTSupply * strategyVaultSettings.maxBalancerPoolShare) / BalancerConstants.VAULT_PERCENT_BASIS;
    }
}
