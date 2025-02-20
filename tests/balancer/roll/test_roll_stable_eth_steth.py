from brownie import accounts
from brownie.network.state import Chain
from tests.fixtures import *
from tests.balancer.helpers import check_invariant, enterMaturity
from scripts.common import (get_deposit_params)

chain = Chain()

def test_single_account_next_maturity_success(StratStableETHstETH):
    (env, vault, mock) = StratStableETHstETH
    primaryBorrowAmount = 5e8
    depositAmount = 10e18
    maturity1 = enterMaturity(env, vault, 1, 0, depositAmount, primaryBorrowAmount, accounts[0])
    maturity2 = env.notional.getActiveMarkets(1)[1][1]
    env.notional.rollVaultPosition(
        accounts[0],
        vault.address,
        primaryBorrowAmount * 1.1,
        maturity2,
        0,
        0,
        0,
        get_deposit_params(),
        {"from": accounts[0]}
    )
    check_invariant(env, vault, [accounts[0]], [maturity1, maturity2])
