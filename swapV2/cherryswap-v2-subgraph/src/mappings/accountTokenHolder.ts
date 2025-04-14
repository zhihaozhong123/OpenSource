/* eslint-disable prefer-const */
import { BigInt, BigDecimal, store,log } from '@graphprotocol/graph-ts'
import {
    AccountTokenHolder,
} from '../types/schema'
import { Transfer,Withdraw} from '../types/templates/Pair/Pair'
import { updatePairDayData, updateTokenDayData, updateUniswapDayData, updatePairHourData } from './dayUpdates'
import { getEthPriceInUSD, findEthPerToken, getTrackedVolumeUSD, getTrackedLiquidityUSD } from './pricing'
import {
  convertTokenToDecimal,
  ADDRESS_ZERO,
  CHERRY_ADDRESS,
  ONE_BI,
  ZERO_BD,
  BI_18
} from './helpers'


export function handleTransfer(event: Transfer): void {
    log.info('begin handleTransfer event', [])
    //忽略掉che产che的pool池的车币转入的事件，所有pool的che的产出记录，所有pool池的车的提现记录。用车的产出记录-车的提现记录剩下的就是收割记录了。
    //去掉所有的流动性的转入转出地址的事件。
    // ignore initial transfers for first adds
    if (event.params.to.toHexString() == ADDRESS_ZERO && event.params.value.equals(BigInt.fromI32(1000))) {
        return
    }
    let transactionHash = event.transaction.hash.toHexString();
    log.info('handleTransfer hash is{}', [transactionHash]);
    let account_token_holder = new AccountTokenHolder(transactionHash);
    
    let from = event.params.from;
    let to = event.params.to;
    let amount = convertTokenToDecimal(event.params.value, BI_18);
    let blockNumber = event.block.number;
    let timestamp = event.block.timestamp;
    account_token_holder.from = from;
    account_token_holder.to = to;
    account_token_holder.amount = amount;
    account_token_holder.height=blockNumber;
    account_token_holder.timestamp = timestamp;
    account_token_holder.save();
}

export function handleWithDraw(event: Withdraw): void {
    log.info('-------------------begin WithDraw event', [])
    //忽略掉che产che的pool池的车币转入的事件，所有pool的che的产出记录，所有pool池的车的提现记录。用车的产出记录-车的提现记录剩下的就是收割记录了。
    //去掉所有的流动性的转入转出地址的事件。
    // ignore initial transfers for first adds
    
    let transactionHash = event.transaction.hash.toHexString();
    log.info('handleTransfer hash is{}', [transactionHash]);
    let account_token_holder = new AccountTokenHolder(transactionHash);
    let symbol = "che-che pool";
    let from = event.transaction.from;
    let to = event.params.user;
    let amount = convertTokenToDecimal(event.params.amount, BI_18);
    let blockNumber = event.block.number;
    let timestamp = event.block.timestamp;
    account_token_holder.symbol=symbol;
    account_token_holder.from = from;
    account_token_holder.to = to;
    account_token_holder.amount = amount;
    account_token_holder.height=blockNumber;
    account_token_holder.timestamp = timestamp;
    account_token_holder.save();
}