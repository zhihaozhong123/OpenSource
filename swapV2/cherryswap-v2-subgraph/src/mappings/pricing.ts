/* eslint-disable prefer-const */
import { Pair, Token, Bundle } from '../types/schema'
import { BigDecimal, Address } from '@graphprotocol/graph-ts/index'
import { ZERO_BD, factoryContract, ADDRESS_ZERO, ONE_BD } from './helpers'
import { log } from '@graphprotocol/graph-ts'

const WOKT_ADDRESS = '0x8f8526dbfd6e38e3d8307702ca8469bae6c56c15'

const BUSD_WOKT_PAIR = '' // created block 589414

const DAI_WOKT_PAIR = ''  // created block 481116

const USDT_WOKT_PAIR = '0xf3098211d012ff5380a03d80f150ac6e5753caa8' // created block 1399395

export function getEthPriceInUSD(): BigDecimal {
  // fetch eth prices for each stablecoin
  let usdtPair = Pair.load(USDT_WOKT_PAIR) // usdt is token0
  // let busdPair = Pair.load(BUSD_WOKT_PAIR) // busd is token1
  let busdPair = Pair.load(BUSD_WOKT_PAIR) // busd is token1
  let daiPair = Pair.load(DAI_WOKT_PAIR)   // dai is token0\

  // all 3 have been created
  // if (daiPair !== null && busdPair !== null && usdtPair !== null) {
  //   let totalLiquidityBNB = daiPair.reserve0.plus(busdPair.reserve0).plus(usdtPair.reserve0)
  //   let daiWeight = daiPair.reserve0.div(totalLiquidityBNB)
  //   let busdWeight = busdPair.reserve0.div(totalLiquidityBNB)
  //   let usdtWeight = usdtPair.reserve0.div(totalLiquidityBNB)
  //   return daiPair.token1Price
  //     .times(daiWeight)
  //     .plus(busdPair.token1Price.times(busdWeight))
  //     .plus(usdtPair.token1Price.times(usdtWeight))
  //   // busd and usdt have been created
  // } else if (busdPair !== null && usdtPair !== null) {
  //   let totalLiquidityBNB = busdPair.reserve0.plus(usdtPair.reserve0)
  //   let busdWeight = busdPair.reserve0.div(totalLiquidityBNB)
  //   let usdtWeight = usdtPair.reserve0.div(totalLiquidityBNB)
  //   return busdPair.token1Price.times(busdWeight).plus(usdtPair.token1Price.times(usdtWeight))
  //   // usdt is the only pair so far
  // } else if (busdPair !== null) {
  //   return busdPair.token1Price
  // } else if (usdtPair !== null) {
  //   return usdtPair.token1Price
  // } else {
  //   return ZERO_BD
  // }
    if (usdtPair !== null) {
      return usdtPair.token1Price
    } else {
      return ZERO_BD
    }
}

// token where amounts should contribute to tracked volume and liquidity
let WHITELIST: string[] = [
  WOKT_ADDRESS, //WOKT
  '0x54e4622dc504176b3bb432dccaf504569699a7ff', //BTCK
  '0xef71ca2ee68f45b9ad6f72fbdb33d707b872315c', //ETHK
  '0x382bb369d343125bfb2117af9c149795c6c65c50', //USDT
]
// minimum liquidity for price to get tracked
let MINIMUM_LIQUIDITY_THRESHOLD_ETH = BigDecimal.fromString('2')

/**
 * Search through graph to find derived Eth per token.
 * @todo update to be derived ETH (add stablecoin estimates)
 **/
export function findEthPerToken(token: Token): BigDecimal {
  if (token.id == WOKT_ADDRESS) {
    return ONE_BD
  }
  // loop through whitelist and check if paired with any
  for (let i = 0; i < WHITELIST.length; ++i) {
    let pairAddress = factoryContract.getPair(Address.fromString(token.id), Address.fromString(WHITELIST[i]))
    if (pairAddress.toHexString() != ADDRESS_ZERO) {
      let pair = Pair.load(pairAddress.toHexString())
      if (pair.token0 == token.id && pair.reserveETH.gt(MINIMUM_LIQUIDITY_THRESHOLD_ETH)) {
        let token1 = Token.load(pair.token1)
        return pair.token1Price.times(token1.derivedETH as BigDecimal) // return token1 per our token * Eth per token 1
      }
      if (pair.token1 == token.id && pair.reserveETH.gt(MINIMUM_LIQUIDITY_THRESHOLD_ETH)) {
        let token0 = Token.load(pair.token0)
        return pair.token0Price.times(token0.derivedETH as BigDecimal) // return token0 per our token * ETH per token 0
      }
    }
  }
  return ZERO_BD // nothing was found return 0
}

/**
 * Accepts tokens and amounts, return tracked amount based on token whitelist
 * If one token on whitelist, return amount in that token converted to USD.
 * If both are, return average of two amounts
 * If neither is, return 0
 */
export function getTrackedVolumeUSD(
  tokenAmount0: BigDecimal,
  token0: Token,
  tokenAmount1: BigDecimal,
  token1: Token
): BigDecimal {
  let bundle = Bundle.load('1')
  let price0 = token0.derivedETH.times(bundle.ethPrice)
  let price1 = token1.derivedETH.times(bundle.ethPrice)

  // both are whitelist tokens, take average of both amounts
  if (WHITELIST.includes(token0.id) && WHITELIST.includes(token1.id)) {
    return tokenAmount0
      .times(price0)
      .plus(tokenAmount1.times(price1))
      .div(BigDecimal.fromString('2'))
  }

  // take full value of the whitelisted token amount
  if (WHITELIST.includes(token0.id) && !WHITELIST.includes(token1.id)) {
    return tokenAmount0.times(price0)
  }

  // take full value of the whitelisted token amount
  if (!WHITELIST.includes(token0.id) && WHITELIST.includes(token1.id)) {
    return tokenAmount1.times(price1)
  }

  // neither token is on white list, tracked volume is 0
  return ZERO_BD
}

/**
 * Accepts tokens and amounts, return tracked amount based on token whitelist
 * If one token on whitelist, return amount in that token converted to USD * 2.
 * If both are, return sum of two amounts
 * If neither is, return 0
 */
export function getTrackedLiquidityUSD(
  bundle: Bundle,
  tokenAmount0: BigDecimal,
  token0: Token,
  tokenAmount1: BigDecimal,
  token1: Token
): BigDecimal {
  let price0 = token0.derivedETH.times(bundle.ethPrice)
  let price1 = token1.derivedETH.times(bundle.ethPrice)

  // both are whitelist tokens, take average of both amounts
  if (WHITELIST.includes(token0.id) && WHITELIST.includes(token1.id)) {
    return tokenAmount0.times(price0).plus(tokenAmount1.times(price1))
  }

  // take double value of the whitelisted token amount
  if (WHITELIST.includes(token0.id) && !WHITELIST.includes(token1.id)) {
    return tokenAmount0.times(price0).times(BigDecimal.fromString('2'))
  }

  // take double value of the whitelisted token amount
  if (!WHITELIST.includes(token0.id) && WHITELIST.includes(token1.id)) {
    return tokenAmount1.times(price1).times(BigDecimal.fromString('2'))
  }

  // neither token is on white list, tracked volume is 0
  return ZERO_BD
}
