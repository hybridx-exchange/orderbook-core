import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'
import { BigNumber, bigNumberify } from 'ethers/utils'

import { expandTo18Decimals, mineBlock, encodePrice, printOrder } from './shared/utilities'
import { orderBookFixture } from './shared/fixtures'
import { AddressZero } from 'ethers/constants'

const MINIMUM_LIQUIDITY = bigNumberify(10).pow(3)

chai.use(solidity)

const overrides = {
  gasLimit: 99999999
}

describe('HybridxOrderBook', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 999999999
  })
  const [wallet, other] = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, [wallet])

  let factory: Contract
  let token0: Contract
  let token1: Contract
  let pair: Contract
  let orderBook: Contract
  let orderBookFactory: Contract
  let tokenBase: Contract
  let tokenQuote: Contract
  beforeEach(async () => {
    const fixture = await loadFixture(orderBookFixture)
    factory = fixture.factory
    token0 = fixture.token0
    token1 = fixture.token1
    pair = fixture.pair
    orderBook = fixture.orderBook
    orderBookFactory = fixture.orderBookFactory
    tokenBase = fixture.tokenA
    tokenQuote = fixture.tokenB
  })

  /*it('getAmountOutForMovePrice down:no buy limit order price', async () => {
    await factory.setOrderBookFactory(orderBookFactory.address);
    console.log("price before:", (await orderBook.getPrice()).toString())
    const minAmount = await orderBook.minAmount()
    console.log("minAmount:", minAmount.toString())

    let limitAmount = expandTo18Decimals(1)
    console.log("limitAmount:", limitAmount.toString())

    await tokenQuote.transfer(orderBook.address, limitAmount)
    await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

    let order = await orderBook.marketOrders(1);
    printOrder(order)
    console.log("user orders:", await orderBook.getUserOrders(wallet.address))
    console.log("price after:", (await orderBook.getPrice()).toString())

    let reserves = await orderBook.getReserves()
    console.log("reserve base:", reserves[0].toString())
    console.log("reserve quote:", reserves[1].toString())

    let amountOutRet = await orderBook.getAmountOutForMovePrice(tokenBase.address, limitAmount, reserves[0], reserves[1])
    console.log("amountOutGet:", amountOutRet[0].toString());
    console.log("amountInLeft:", amountOutRet[1].toString());
    console.log("reserveInRet:", amountOutRet[2].toString());
    console.log("reserveOutRet:", amountOutRet[3].toString());
  })*/

  /*it('getAmountOutForMovePrice down:start price == buy limit order price', async () => {
    await factory.setOrderBookFactory(orderBookFactory.address);
    console.log("price before:", (await orderBook.getPrice()).toString())
    const minAmount = await orderBook.minAmount()
    console.log("minAmount:", minAmount.toString())

    let limitAmount = expandTo18Decimals(10)
    console.log("limitAmount:", limitAmount.toString())

    await tokenQuote.transfer(orderBook.address, limitAmount)
    await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

    let order = await orderBook.marketOrders(1);
    printOrder(order)
    console.log("user orders:", await orderBook.getUserOrders(wallet.address))
    console.log("price after:", (await orderBook.getPrice()).toString())

    let reserves = await orderBook.getReserves()
    console.log("reserve base:", reserves[0].toString())
    console.log("reserve quote:", reserves[1].toString())

    limitAmount = bigNumberify("7749174582596444639")//expandTo18Decimals(1)
    let amountOutRet = await orderBook.getAmountOutForMovePrice(tokenBase.address, limitAmount, reserves[0], reserves[1])
    console.log("amountOutGet:", amountOutRet[0].toString());
    console.log("amountInLeft:", amountOutRet[1].toString());
    console.log("reserveInRet:", amountOutRet[2].toString());
    console.log("reserveOutRet:", amountOutRet[3].toString());
  })*/

  it('getAmountOutForMovePrice down:start price > buy limit order price', async () => {
    await factory.setOrderBookFactory(orderBookFactory.address);
    console.log("price before:", (await orderBook.getPrice()).toString())
    const minAmount = await orderBook.minAmount()
    console.log("minAmount:", minAmount.toString())

    let limitAmount = expandTo18Decimals(10)
    console.log("limitAmount:", limitAmount.toString())

    await tokenQuote.transfer(orderBook.address, limitAmount)
    await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address)

    let order = await orderBook.marketOrders(1);
    printOrder(order)
    console.log("user orders:", await orderBook.getUserOrders(wallet.address))
    console.log("price after:", (await orderBook.getPrice()).toString())

    let reserves = await orderBook.getReserves()
    console.log("reserve base:", reserves[0].toString())
    console.log("reserve quote:", reserves[1].toString())

    let amountOutRet = await orderBook.getAmountOutForMovePrice(tokenBase.address, limitAmount, reserves[0], reserves[1])
    console.log("amountOutGet:", amountOutRet[0].toString());
    //10875417928714590749 == 2925820234006285945 + (expandTo18Decimals(10) - 2074179765993714053) * 0.997 * 1
    console.log("amountInLeft:", amountOutRet[1].toString());
    console.log("reserveInRet:", amountOutRet[2].toString());
    console.log("reserveOutRet:", amountOutRet[3].toString());

    const price = bigNumberify("1000000000000000000")
    const decimal = 18
    let results = await orderBook.getAmountForMovePrice(2, reserves[0], reserves[1], price, decimal)
    console.log("amount base:", results[0].toString())
    console.log("amount quote:", results[1].toString())
    console.log("reserve base:", results[2].toString())
    console.log("reserve quote:", results[3].toString())
  })

  //实际情况不存在start price < buy limit order price的情况
})
