import pytest
import brownie
from brownie import ZERO_ADDRESS, accounts
from brownie.network.state import Chain
from scripts.common import get_updated_vault_settings
from tests.balancer.helpers import (
    snapshot_invariants, 
    check_invariants, 
    check_account,
    enterMaturity, 
    exitVaultPercent,
    get_expected_bpt_amount,
    get_expected_borrow_amount
)

chain = Chain()

class ETHPrimaryContext:
    def __init__(self, env, vault, mock) -> None:
        self.env = env
        self.vault = vault
        self.mock = mock
        self.currencyId = 1
        self.token = ZERO_ADDRESS
        self.whale = env.whales["ETH"]
        self.primaryDecimals = 18
    def balance(self, account):
        return account.balance()
    def approve(self, account, target):
        pass
    def transfer(self, dest, amount):
        self.whale.transfer(dest, amount)

class DAIPrimaryContext:
    def __init__(self, env, vault, mock) -> None:
        self.env = env
        self.vault = vault
        self.mock = mock
        self.currencyId = 2
        self.token = env.tokens["DAI"]
        self.whale = env.whales["DAI_EOA"]
        self.token.approve(env.notional.address, 2**256-1, {"from": self.whale})
        self.primaryDecimals = self.token.decimals()
    def balance(self, account):
        return self.token.balanceOf(account)
    def approve(self, account, target):
        self.token.approve(target, 2**256-1, {"from": account})
    def transfer(self, dest, amount):
        self.token.transfer(dest, amount, {"from": self.whale})

class USDCPrimaryContext:
    def __init__(self, env, vault, mock) -> None:
        self.env = env
        self.vault = vault
        self.mock = mock
        self.currencyId = 3
        self.token = env.tokens["USDC"]
        self.whale = env.whales["USDC"]
        self.token.approve(env.notional.address, 2**256-1, {"from": self.whale})
        self.primaryDecimals = self.token.decimals()
    def balance(self, account):
        return self.token.balanceOf(account)
    def approve(self, account, target):
        self.token.approve(target, 2**256-1, {"from": account})
    def transfer(self, dest, amount):
        self.token.transfer(dest, amount, {"from": self.whale})

def deposit(context, ops):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    primaryPrecision = 10**context.primaryDecimals
    maturities = [m[1] for m in notional.getActiveMarkets(currencyId)]
    snapshot = snapshot_invariants(env, vault, maturities)
    depositors = set()
    for op in ops:
        depositAmount = op[0]
        primaryBorrowAmount = op[1]
        depositor = op[2]
        context.approve(depositor, otional.address)
        context.transfer(depositor, depositAmount)
        if depositor not in depositors:
            depositors.add(depositor)
        maturity = maturities[op[3]]
        depositParams = op[4]
        expectedBorrowAmount = get_expected_borrow_amount(env, currencyId, maturity, primaryBorrowAmount)
        expectedBptAmount = get_expected_bpt_amount(context, depositAmount, expectedBorrowAmount)
        enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, depositor, False, depositParams)
        vaultAccount = notional.getVaultAccount(depositor, vault.address)
        vaultState = notional.getVaultState(vault.address, maturity)
        assert vaultAccount["fCash"] == -primaryBorrowAmount
        strategyTokens = vaultAccount["vaultShares"] * vaultState["totalStrategyTokens"] / vaultState["totalVaultShares"]
        assert pytest.approx(vault.convertStrategyTokensToBPTClaim(strategyTokens), rel=1e-5) == expectedBptAmount
        underlyingValue = vault.convertStrategyToUnderlying(depositor, vaultAccount["vaultShares"], maturity)
        assert pytest.approx(underlyingValue, rel=5e-2) == depositAmount + primaryBorrowAmount * primaryPrecision / 1e8
    check_invariants(env, vault, list(depositors), maturities, snapshot)

def redeem(context, ops):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    maturities = [m[1] for m in notional.getActiveMarkets(currencyId)]
    maturity = maturities[0]
    snapshot = snapshot_invariants(env, vault, maturities)
    depositors = set()
    for op in ops:
        depositAmount = op[0]
        primaryBorrowAmount = op[1]
        depositor = op[2]
        context.approve(depositor, notional.address)
        context.transfer(depositor, depositAmount)
        if depositor not in depositors:
            depositors.add(depositor)
        maturity = maturities[op[3]]
        redeemParams = op[4]
        percentages = op[5]
        enterMaturity(env, vault, currencyId, maturity, depositAmount, primaryBorrowAmount, depositor)
        firstRedeem = True
        primaryAmountBefore = context.balance(depositor)
        totalfCashRepaid = 0
        for percentage in percentages:
            vaultShares = notional.getVaultAccount(depositor, vault.address)["vaultShares"]
            if firstRedeem:
                # Min entry blocks
                with brownie.reverts():
                    exitVaultPercent(env, vault, depositor, percentage, redeemParams, True)
                chain.mine(5)

            (sharesRedeemed, fCashRepaid) = exitVaultPercent(env, vault, depositor, percentage, redeemParams)
            totalfCashRepaid += fCashRepaid
            check_account(env, vault, depositor, vaultShares - sharesRedeemed, primaryBorrowAmount - totalfCashRepaid)
            assert pytest.approx(context.balance(depositor) - primaryAmountBefore, rel=5e-2) == depositAmount * percentage
            firstRedeem = False
    check_invariants(env, vault, depositors, maturities, snapshot)

def normal_settlement(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.depositor
    primaryPrecision = 10**context.primaryDecimals

def post_maturity_settlement(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.depositor
    primaryPrecision = 10**context.primaryDecimals

def emergency_settlement(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.depositor
    primaryPrecision = 10**context.primaryDecimals

def roll(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.depositor
    primaryPrecision = 10**context.primaryDecimals

def leverage_ratio_too_high(context, depositAmount, primaryBorrowAmount):
    env = context.env
    notional = env.notional
    vault = context.vault
    currencyId = context.currencyId
    depositor = context.whale
    maturities = [m[1] for m in notional.getActiveMarkets(currencyId)]
    with brownie.reverts("Insufficient Collateral"):
        enterMaturity(env, vault, currencyId, maturities[0], depositAmount, primaryBorrowAmount, depositor, True)

def balancer_share_too_high(context, depositAmount, primaryBorrowAmount):
    env = context.env
    vault = context.vault
    settings = vault.getStrategyContext()["baseStrategy"]["vaultSettings"]
    # Only Notional owner can change settings
    with brownie.reverts():
        vault.setStrategyVaultSettings.call(
            get_updated_vault_settings(settings, maxBalancerPoolShare=0),
            {"from": accounts[0]}
        )
    vault.setStrategyVaultSettings(
        get_updated_vault_settings(settings, maxBalancerPoolShare=0),
        {"from": env.notional.owner()}
    )
    with brownie.reverts():
        enterMaturity(env, vault, 2, 0, depositAmount, primaryBorrowAmount, env.whales["DAI_EOA"], True)

