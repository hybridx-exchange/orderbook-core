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

  /*it('create:buy limit order', async () => {
    await factory.setOrderBookFactory(orderBookFactory.address);
    console.log("price before:", (await orderBook.getPrice()).toString())
    const minAmount = await orderBook.minAmount()
    console.log("minAmount:", minAmount.toString())

    const limitAmount = expandTo18Decimals(10)
    console.log("limitAmount:", limitAmount.toString())
    await tokenQuote.transfer(orderBook.address, limitAmount)

    await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address))
        .to.emit(orderBook, 'OrderCreated')
        .withArgs(wallet.address, wallet.address, limitAmount, limitAmount, expandTo18Decimals(2), 1)

    const order = await orderBook.marketOrders(1);
    printOrder(order)
    console.log("market book:", await orderBook.marketBook(1, 1))
    console.log("range book:", await orderBook.rangeBook(1, expandTo18Decimals(2)))
    console.log("user order:", await orderBook.userOrders(wallet.address, 0))
    console.log("user orders:", await orderBook.getUserOrders(wallet.address))

    console.log("price after:", (await orderBook.getPrice()).toString())
  })

  it('create:sell limit order', async () => {
    await factory.setOrderBookFactory(orderBookFactory.address);
    console.log("price before:", (await orderBook.getPrice()).toString())
    const minAmount = await orderBook.minAmount()
    console.log("minAmount:", minAmount.toString())

    const limitAmount = expandTo18Decimals(10)
    console.log("limitAmount:", limitAmount.toString())
    await tokenBase.transfer(orderBook.address, limitAmount)

    await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address))
        .to.emit(orderBook, 'OrderCreated')
        .withArgs(wallet.address, wallet.address, limitAmount, limitAmount, expandTo18Decimals(2), 2)

    const order = await orderBook.marketOrders(1);
    printOrder(order)
    console.log("market book:", await orderBook.marketBook(2, 1))
    console.log("range book:", await orderBook.rangeBook(2, expandTo18Decimals(2)))
    console.log("user order:", await orderBook.userOrders(wallet.address, 0))
    console.log("user orders:", await orderBook.getUserOrders(wallet.address))

    console.log("price after:", (await orderBook.getPrice()).toString())
  })*/

  it('create:buy limit order and partial fulfill', async () => {
    await factory.setOrderBookFactory(orderBookFactory.address);
    console.log("price before:", (await orderBook.getPrice()).toString())
    const minAmount = await orderBook.minAmount()
    console.log("minAmount:", minAmount.toString())

    const limitAmount = expandTo18Decimals(5)
    console.log("limitAmount:", limitAmount.toString())
    await tokenQuote.transfer(orderBook.address, limitAmount)

    await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address, overrides))
        .to.emit(orderBook, 'OrderCreated')

    const order = await orderBook.marketOrders(1)
    printOrder(order)
    //console.log("market book:", await orderBook.marketBook(1, 1))
    //console.log("range book:", await orderBook.rangeBook(1, expandTo18Decimals(3)))
    //console.log("user order:", await orderBook.userOrders(wallet.address, 0))
    //console.log("user orders:", await orderBook.getUserOrders(wallet.address))

    console.log("price after:", (await orderBook.getPrice()).toString())
  })

  /*it('create:sell limit order and partial fulfill', async () => {
    await factory.setOrderBookFactory(orderBookFactory.address);

    console.log("price before:", (await orderBook.getPrice()).toString())
    //const minAmount = await orderBook.minAmount()
    //console.log("minAmount:", minAmount.toString())

    const limitAmount = expandTo18Decimals(14)
    //console.log("limitAmount:", limitAmount.toString())
    await tokenBase.transfer(orderBook.address, limitAmount)

    //await expect(orderBook.createSellLimitOrder(wallet.address, bigNumberify("1389583680700000000"),
     //wallet.address, overrides))
        //.to.emit(orderBook, 'OrderCreated')
    await expect(orderBook.createSellLimitOrder(wallet.address, bigNumberify("1000000000000000000"),
        wallet.address, overrides))
        .to.emit(orderBook, 'OrderCreated')

    const order = await orderBook.marketOrders(1)
    printOrder(order)

    //console.log("market book:", await orderBook.marketBook(2, 1))
    //console.log("range book:", await orderBook.rangeBook(2, expandTo18Decimals(2)))
    //console.log("user order:", await orderBook.userOrders(wallet.address, 0))
    //console.log("user orders:", await orderBook.getUserOrders(wallet.address))

    console.log("price after:", (await orderBook.getPrice()).toString())
  })*/

  /*it('create:gas', async () => {
    await factory.setOrderBookFactory(orderBookFactory.address);
    await tokenBase.transfer(orderBook.address, expandTo18Decimals(10))
    const tx = await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address)
    const receipt = await tx.wait()
    console.log(receipt.gasUsed.toString())
  })*/
})
