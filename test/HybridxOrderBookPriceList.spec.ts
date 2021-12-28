import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'
import { BigNumber, bigNumberify } from 'ethers/utils'

import { expandTo18Decimals, mineBlock, encodePrice } from './shared/utilities'
import { orderBookFixture } from './shared/fixtures'
import { AddressZero } from 'ethers/constants'

const MINIMUM_LIQUIDITY = bigNumberify(10).pow(3)

chai.use(solidity)

const overrides = {
  gasLimit: 19999999
}

describe('HybridxOrderBook', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 19999999
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

  /*it('priceList test', async () => {
    let limitAmount = expandTo18Decimals(1)
    let limitPrices = [
      bigNumberify("3100000000000000000"),
      bigNumberify("3200000000000000000"),
      bigNumberify("3300000000000000000"),
      bigNumberify("3400000000000000000"),
      bigNumberify("3500000000000000000"),
      bigNumberify("3600000000000000000"),
      bigNumberify("3700000000000000000"),
      bigNumberify("3800000000000000000")]
    for (let i=0; i<limitPrices.length; i++) {
      await tokenBase.transfer(orderBook.address, limitAmount)
      await orderBook.createSellLimitOrder(wallet.address, limitPrices[i], wallet.address, overrides)
    }

    let next = await orderBook.nextPrice(bigNumberify(2), bigNumberify(0))
    console.log("next:", next.toString())
    while(!next.eq(bigNumberify(0))){
      next = await orderBook.nextPrice(bigNumberify(2), next)
      console.log("next:", next.toString())
    }

    let result = await orderBook.rangeBook(bigNumberify(2), expandTo18Decimals(4))
    console.log(result)
  })*/
})
