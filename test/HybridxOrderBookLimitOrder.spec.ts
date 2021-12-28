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

  /*it('create:buy limit order market', async () => {
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
    //console.log("market book:", await orderBook.marketBook(1, 1))
    //console.log("range book:", await orderBook.rangeBook(1, expandTo18Decimals(2)))
    console.log("user orders:", await orderBook.getUserOrders(wallet.address))

    console.log("price after:", (await orderBook.getPrice()).toString())
  })*/

  /*it('create:buy limit order market2', async () => {
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
    //console.log("market book:", await orderBook.marketBook(1, 1))
    //console.log("range book:", await orderBook.rangeBook(1, expandTo18Decimals(2)))
    console.log("user orders:", await orderBook.getUserOrders(wallet.address))

    console.log("price after:", (await orderBook.getPrice()).toString())
  })*/

  /*it('create:sell limit order market', async () => {
    await factory.setOrderBookFactory(orderBookFactory.address);
    console.log("price before:", (await orderBook.getPrice()).toString())
    const minAmount = await orderBook.minAmount()
    console.log("minAmount:", minAmount.toString())

    let limitAmount = expandTo18Decimals(1)
    console.log("limitAmount:", limitAmount.toString())



    await tokenBase.transfer(orderBook.address, limitAmount)
    await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address)

    let order = await orderBook.marketOrders(1);
    printOrder(order)
    console.log("market book:", await orderBook.marketBook(2, 1))
    console.log("range book:", await orderBook.rangeBook(2, expandTo18Decimals(2)))
    console.log("user orders:", await orderBook.getUserOrders(wallet.address))
    console.log("price after:", (await orderBook.getPrice()).toString())
  })*/

  /*it('create:sell limit order market2', async () => {
    await factory.setOrderBookFactory(orderBookFactory.address);
    console.log("price before:", (await orderBook.getPrice()).toString())
    const minAmount = await orderBook.minAmount()
    console.log("minAmount:", minAmount.toString())

    let limitAmount = expandTo18Decimals(2)//bigNumberify("2074179765993714054")//expandTo18Decimals(1)
    console.log("limitAmount:", limitAmount.toString())

    await tokenBase.transfer(orderBook.address, limitAmount)
    await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address)

    let order = await orderBook.marketOrders(0);
    printOrder(order)
    console.log("range book:", await orderBook.rangeBook(2, expandTo18Decimals(1)))
    console.log("user orders:", await orderBook.getUserOrders(wallet.address))

    console.log("price after:", (await orderBook.getPrice()).toString())
    console.log("base amount:", (await tokenBase.balanceOf(pair.address)).toString())
    console.log("quote amount:", (await tokenQuote.balanceOf(pair.address)).toString())
  })*/

  it('create:buy then sell limit order match', async () => {
    await factory.setOrderBookFactory(orderBookFactory.address);
    console.log("price before:", (await orderBook.getPrice()).toString())
    const minAmount = await orderBook.minAmount()
    console.log("minAmount:", minAmount.toString())

    let limitAmount = expandTo18Decimals(1)
    console.log("limitAmount:", limitAmount.toString())

    await tokenQuote.transfer(orderBook.address, limitAmount)
    await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address)

    let order = await orderBook.marketOrders(1);
    printOrder(order)
    console.log("market book:", await orderBook.marketBook(1, 1))
    console.log("range book:", await orderBook.rangeBook(1, expandTo18Decimals(2)))
    console.log("user order:", await orderBook.userOrders(wallet.address, 0))
    console.log("user orders:", await orderBook.getUserOrders(wallet.address))

    console.log("price after1:", (await orderBook.getPrice()).toString())

    limitAmount = expandTo18Decimals(2)
    await tokenBase.transfer(orderBook.address, limitAmount)
    await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address)

    order = await orderBook.marketOrders(1);
    printOrder(order)
    order = await orderBook.marketOrders(2);
    printOrder(order)
    console.log("market book:", await orderBook.marketBook(2, 1))
    console.log("range book:", await orderBook.rangeBook(2, expandTo18Decimals(3)))
    //console.log("user orders:", await orderBook.getUserOrders(wallet.address))

    console.log("price after2:", (await orderBook.getPrice()).toString())
  })

  /*it('create:sell then buy limit order match', async () => {
    await factory.setOrderBookFactory(orderBookFactory.address);
    console.log("price before:", (await orderBook.getPrice()).toString())
    const minAmount = await orderBook.minAmount()
    console.log("minAmount:", minAmount.toString())

    const price = expandTo18Decimals(2)
    const decimal = 18

    let limitAmount0 = expandTo18Decimals(10)
    console.log("limitAmount:", limitAmount0.toString())

    await tokenBase.transfer(orderBook.address, limitAmount0)
    await orderBook.createSellLimitOrder(wallet.address, price, wallet.address)

    let order = await orderBook.marketOrders(1);
    printOrder(order)
    //console.log("market book:", await orderBook.marketBook(2, 1))
    //console.log("range book:", await orderBook.rangeBook(2, expandTo18Decimals(2)))
    //console.log("user orders:", await orderBook.getUserOrders(wallet.address))

    console.log("price after1:", (await orderBook.getPrice()).toString())

    let limitAmount = expandTo18Decimals(30)
    //let results2 = await orderBook._getAmountAndTakePrice2(1, limitAmount, price, decimal, limitAmount0)
    //console.log(results2)
    //console.log("amount in", results2[0].toString())
    //console.log("amount out with fee", results2[1].toString())
    //console.log("fee", results2[2].toString())

    await tokenQuote.transfer(orderBook.address, limitAmount)
    await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

    order = await orderBook.marketOrders(1);
    printOrder(order)
    order = await orderBook.marketOrders(2);
    printOrder(order)
    console.log("market book:", await orderBook.marketBook(1, 1))
    console.log("range book:", await orderBook.rangeBook(1, expandTo18Decimals(3)))
    console.log("user orders:", await orderBook.getUserOrders(wallet.address))

    console.log("price after2:", (await orderBook.getPrice()).toString())
  })*/
})
