import json
import re
import eth_abi
from brownie import network, Contract
from brownie.network.state import Chain

chain = Chain()

DEX_ID = {
    'UNISWAP_V2': 0,
    'UNISWAP_V3': 1,
    'ZERO_EX': 2,
    'BALANCER_V2': 3,
    'CURVE': 4,
    'NOTIONAL_VAULT': 5
}

TRADE_TYPE = {
    'EXACT_IN_SINGLE': 0,
    'EXACT_OUT_SINGLE': 1,
    'EXACT_IN_BATCH': 2,
    'EXACT_OUT_BATCH': 3
}

def getDependencies(bytecode):
    deps = set()
    for marker in re.findall("_{1,}[^_]*_{1,}", bytecode):
        deps.add(marker)
    result = list(deps)
    return result

def deployArtifact(path, constructorArgs, deployer, name, libs=None):
    with open(path, "r") as a:
        artifact = json.load(a)

    code = artifact["bytecode"]

    # Resolve dependencies
    deps = getDependencies(code)

    for dep in deps:
        library = dep.strip("_")
        code = code.replace(dep, libs[library][-40:])

    createdContract = network.web3.eth.contract(abi=artifact["abi"], bytecode=code)
    txn = createdContract.constructor(*constructorArgs).buildTransaction(
        {"from": deployer.address, "nonce": deployer.nonce}
    )
    # This does a manual deployment of a contract
    tx_receipt = deployer.transfer(data=txn["data"])

    return Contract.from_abi(name, tx_receipt.contract_address, abi=artifact["abi"], owner=deployer)

def get_vault_config(**kwargs):
    return [
        kwargs.get("flags", 0),  # 0: flags
        kwargs.get("currencyId", 1),  # 1: currency id
        kwargs.get("minAccountBorrowSize", 100_000),  # 2: min account borrow size
        kwargs.get("minCollateralRatioBPS", 2000),  # 3: 20% collateral ratio
        kwargs.get("feeRate5BPS", 20),  # 4: 1% fee
        kwargs.get("liquidationRate", 104),  # 5: 4% liquidation discount
        kwargs.get("reserveFeeShare", 20),  # 6: 20% reserve fee share
        kwargs.get("maxBorrowMarketIndex", 2),  # 7: 20% reserve fee share
        kwargs.get("maxDeleverageCollateralRatioBPS", 4000),  # 8: 40% max collateral ratio
        kwargs.get("secondaryBorrowCurrencies", [0, 0, 0]),  # 9: none set
    ]

def set_flags(flags, **kwargs):
    binList = list(format(flags, "b").rjust(16, "0"))
    if "ENABLED" in kwargs:
        binList[0] = "1"
    if "ALLOW_ROLL_POSITION" in kwargs:
        binList[1] = "1"
    if "ONLY_VAULT_ENTRY" in kwargs:
        binList[2] = "1"
    if "ONLY_VAULT_EXIT" in kwargs:
        binList[3] = "1"
    if "ONLY_VAULT_ROLL" in kwargs:
        binList[4] = "1"
    if "ONLY_VAULT_DELEVERAGE" in kwargs:
        binList[5] = "1"
    if "ONLY_VAULT_SETTLE" in kwargs:
        binList[6] = "1"
    if "TRANSFER_SHARES_ON_DELEVERAGE" in kwargs:
        binList[7] = "1"
    if "ALLOW_REENTRNACY" in kwargs:
        binList[8] = "1"
    return int("".join(reversed(binList)), 2)

def get_updated_vault_settings(settings, **kwargs):
    return [
        kwargs.get("maxUnderlyingSurplus", settings["maxUnderlyingSurplus"]), 
        kwargs.get("oracleWindowInSeconds", settings["oracleWindowInSeconds"]), 
        kwargs.get("settlementSlippageLimitPercent", settings["settlementSlippageLimitPercent"]), 
        kwargs.get("postMaturitySettlementSlippageLimitPercent", settings["postMaturitySettlementSlippageLimitPercent"]), 
        kwargs.get("maxBalancerPoolShare", settings["maxBalancerPoolShare"]), 
        kwargs.get("balancerOracleWeight", settings["balancerOracleWeight"]), 
        kwargs.get("settlementCoolDownInMinutes", settings["settlementCoolDownInMinutes"]), 
        kwargs.get("postMaturitySettlementCoolDownInMinutes", settings["postMaturitySettlementCoolDownInMinutes"]), 
        kwargs.get("feePercentage", settings["feePercentage"])
    ]

def get_univ3_single_data(fee):
    return eth_abi.encode_abi(['(uint24)'], [[fee]])

def get_univ3_batch_data(path):
    return eth_abi.encode_abi(['(bytes)'], [[path]])

def get_deposit_trade_params(dexId, tradeType, amount, slippage, exchangeData):
    return eth_abi.encode_abi(
        ['(uint16,uint8,uint32,uint256,bytes))'],
        [[
            dexId,
            tradeType,
            amount,
            slippage,
            exchangeData
        ]]
    )

def get_deposit_params(minBPT=0, secondaryBorrow=0, trade=bytes(0)):
    return eth_abi.encode_abi(
        ['(uint256,uint256,uint32,uint32,bytes)'],
        [[
            minBPT,
            secondaryBorrow,
            0, # secondaryBorrowLimit
            0, # secondaryRollLendLimit
            trade
        ]]
    )