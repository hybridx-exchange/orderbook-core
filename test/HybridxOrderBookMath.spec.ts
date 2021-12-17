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

  /*it('getAmountForAmmMovePrice: current price == target price', async () => {
    console.log("price before:", (await orderBook.getPrice()).toString())

    console.log("base", tokenBase.address)
    console.log("quote", tokenQuote.address)
    console.log("token0", token0.address)
    console.log("token1", token1.address)

    const reserves = await orderBook.getReserves()
    console.log(reserves[0].toString())
    console.log(reserves[1].toString())
    const price = expandTo18Decimals(2)
    const decimal = 18

    let results = await orderBook.getAmountForAmmMovePrice(2, reserves[0], reserves[1], price, decimal)
    console.log(results[0].toString())
    console.log(results[1].toString())
    console.log(results[2].toString())
    console.log(results[3].toString())
  })

  it('getAmountForAmmMovePrice: current price < target price', async () => {
    console.log("price before:", (await orderBook.getPrice()).toString())

    console.log("base", tokenBase.address)
    console.log("quote", tokenQuote.address)
    console.log("token0", token0.address)
    console.log("token1", token1.address)

    const reserves = await orderBook.getReserves()
    console.log(reserves[0].toString())
    console.log(reserves[1].toString())
    const price = expandTo18Decimals(3)
    const decimal = 18

    let results = await orderBook.getAmountForAmmMovePrice(2, reserves[0], reserves[1], price, decimal)
    console.log(results[0].toString())
    console.log(results[1].toString())
    console.log(results[2].toString())
    console.log(results[3].toString())
  })

  it('getAmountForAmmMovePrice: current price << target price', async () => {
    console.log("price before:", (await orderBook.getPrice()).toString())

    console.log("base", tokenBase.address)
    console.log("quote", tokenQuote.address)
    console.log("token0", token0.address)
    console.log("token1", token1.address)

    const reserves = await orderBook.getReserves()
    console.log(reserves[0].toString())
    console.log(reserves[1].toString())
    const price = expandTo18Decimals(200)
    const decimal = 18

    let results = await orderBook.getAmountForAmmMovePrice(2, reserves[0], reserves[1], price, decimal)
    console.log(results[0].toString())
    console.log(results[1].toString())
    console.log(results[2].toString())
    console.log(results[3].toString())
  })

  it('getAmountForAmmMovePrice: current price > target price', async () => {
    console.log("price before:", (await orderBook.getPrice()).toString())

    console.log("base", tokenBase.address)
    console.log("quote", tokenQuote.address)
    console.log("token0", token0.address)
    console.log("token1", token1.address)

    const reserves = await orderBook.getReserves()
    console.log(reserves[0].toString())
    console.log(reserves[1].toString())
    const price = bigNumberify("1389583680700000000")
    const decimal = 18

    let results = await orderBook.getAmountForAmmMovePrice(2, reserves[0], reserves[1], price, decimal)
    console.log(results[0].toString())
    console.log(results[1].toString())
    console.log(results[2].toString())
    console.log(results[3].toString())
  })

  it('getAmountForAmmMovePrice: current price >> target price', async () => {
    console.log("price before:", (await orderBook.getPrice()).toString())

    console.log("base", tokenBase.address)
    console.log("quote", tokenQuote.address)
    console.log("token0", token0.address)
    console.log("token1", token1.address)

    const reserves = await orderBook.getReserves()
    console.log(reserves[0].toString())
    console.log(reserves[1].toString())
    const price = bigNumberify("1")
    const decimal = 18

    let results = await orderBook.getAmountForAmmMovePrice(2, reserves[0], reserves[1], price, decimal)
    console.log(results[0].toString())
    console.log(results[1].toString())
    console.log(results[2].toString())
    console.log(results[3].toString())
  })*/

  /*it('getAmountForAmmMovePrice: 2 -> 1', async () => {
    console.log("price before:", (await orderBook.getPrice()).toString())

    //console.log("base", tokenBase.address)
    //console.log("quote", tokenQuote.address)
    //console.log("token0", token0.address)
    //console.log("token1", token1.address)

    const reserves = await orderBook.getReserves()
    console.log(reserves[0].toString())
    console.log(reserves[1].toString())
    const price = bigNumberify("1000000000000000000")
    const decimal = 18

    let results = await orderBook.getAmountForOrderBookMovePrice(2, reserves[0], reserves[1], price, decimal)
    console.log("amount base:", results[0].toString())
    console.log("amount quote:", results[1].toString())
    console.log("reserve base:", results[2].toString())
    console.log("reserve quote:", results[3].toString())

    let amountQuote1 = await orderBook.getAmountOut(results[0], reserves[0], reserves[1]);
    console.log("amountQuote1:", amountQuote1.toString())

    let amountQuote2 = await orderBook.getAmountQuoteForPriceDown(bigNumberify(results[0]), reserves[0], reserves[1], price, decimal)
    console.log("amountQuote2:", amountQuote2.toString())

    let results2 = await orderBook._getFixAmountForMovePriceDown(bigNumberify(1), results[0], results[2], results[3], price)
    console.log(results2[0].toString(), results2[1].toString())

    console.log("price swap:", (results[1].mul(bigNumberify(10).pow(18)).div(results[0])).toString());

    console.log("price after:", (results[3].mul(bigNumberify(10).pow(18)).div(results[2])).toString());
  })*/

  /*it('getAmountForAmmMovePrice: 2 -> 3', async () => {
    //console.log("base", tokenBase.address)
    //console.log("quote", tokenQuote.address)
    //console.log("token0", token0.address)
    //console.log("token1", token1.address)

    let reserves = await orderBook.getReserves()
    console.log("reserve base:", reserves[0].toString())
    console.log("reserve quote:", reserves[1].toString())
    console.log("price before:", (await orderBook.getPrice()).toString())
    const price = bigNumberify("2419340000000000000")//453305446940074565
    const decimal = 18

    let results = await orderBook.getAmountForOrderBookMovePrice(1, reserves[0], reserves[1], price, decimal)
    console.log("amount base:", results[0].toString())
    console.log("amount quote:", results[1].toString())
    console.log("reserve base:", results[2].toString())
    console.log("reserve quote:", results[3].toString())

    let amountBase1 = await orderBook.getAmountOut(bigNumberify(results[1]), reserves[1], reserves[0])
    console.log("amountBase1:", amountBase1.toString())

    let amountBase2 = await orderBook.getAmountBaseForPriceUp(results[1], reserves[0], reserves[1], price, decimal)
    console.log("amountBase2:", amountBase2.toString())

    console.log("price swap:", (results[1].mul(bigNumberify(10).pow(18)).div(results[0])).toString())

    console.log("price after:", (results[3].mul(bigNumberify(10).pow(18)).div(results[2])).toString())

    results = await orderBook._getFixAmountForMovePriceUp(bigNumberify("10000000000000000000"), results[1], results[2], results[3], price)
    console.log("amountBase3", results[0].toString(), results[1].toString())

    //console.log("price after2:", (amountQuote3.mul(bigNumberify(10).pow(18)).div(results[2])).toString())

    await tokenQuote.transfer(pair.address, results[1], overrides)
    await pair.swap(amountBase3, bigNumberify(0), wallet.address, '0x', overrides)
    console.log("price after3:", (await orderBook.getPrice()).toString())
    await pair.sync(overrides)
    console.log("price after4:", (await orderBook.getPrice()).toString())
  })*/
  /*it('getAmountForAmmMovePrice: 2 -> 3', async () => {
    let reserves = await orderBook.getReserves()
    console.log("reserve base:", reserves[0].toString())
    console.log("reserve quote:", reserves[1].toString())
    console.log("price before:", (await orderBook.getPrice()).toString())
    const price = bigNumberify("2419340000000000000")//453305446940074565
    const decimal = 18

    let results = await orderBook._ammMovePrice(1, reserves[0], reserves[1], price,
        bigNumberify("9000000000000000000"), bigNumberify(0), bigNumberify(0))
    console.log("amount left:", results[0].toString())
    console.log("reserve base:", results[1].toString())
    console.log("reserve quote:", results[2].toString())
    console.log("amount base:", results[3].toString())
    console.log("amount quote:", results[4].toString())

    console.log("price after:", (results[2].mul(bigNumberify(10).pow(18)).div(results[1])).toString())

    let results2 = await orderBook._getFixAmountForMovePriceUp(results[0], results[4], results[1], results[2], price)
    console.log("amountBase3", results2[0].toString(), results2[1].toString())

    let amountBase1 = await orderBook.getAmountOut(bigNumberify(results[4]), reserves[1], reserves[0])
    console.log("amountBase1:", amountBase1.toString())

    let amountBase2 = await orderBook.getAmountBaseForPriceUp(results[4], reserves[0], reserves[1], price, decimal)
    console.log("amountBase2:", amountBase2.toString())

    console.log("price swap:", (results[4].mul(bigNumberify(10).pow(18)).div(results[3])).toString())

    console.log("price after:", (results[2].mul(bigNumberify(10).pow(18)).div(results[1])).toString())
  })*/
})
