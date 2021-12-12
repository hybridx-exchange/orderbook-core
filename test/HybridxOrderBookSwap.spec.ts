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
  gasLimit: 999999999
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

  it('swap:no limit order', async () => {
    console.log("price before:", (await orderBook.getPrice()).toString())

    const token0Amount = await token0.balanceOf(pair.address)
    const token1Amount = await token1.balanceOf(pair.address)
    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = bigNumberify('1662497915624478906')
    await token0.transfer(pair.address, swapAmount)
    await expect(pair.swap(0, expectedOutputAmount, wallet.address, '0x', overrides))
        .to.emit(token1, 'Transfer')
        .withArgs(pair.address, wallet.address, expectedOutputAmount)
        .to.emit(pair, 'Sync')
        .withArgs(token0Amount.add(swapAmount), token1Amount.sub(expectedOutputAmount))
        .to.emit(pair, 'Swap')
        .withArgs(wallet.address, swapAmount, 0, 0, expectedOutputAmount, wallet.address)

    const reserves = await pair.getReserves()
    expect(reserves[0]).to.eq(token0Amount.add(swapAmount))
    expect(reserves[1]).to.eq(token1Amount.sub(expectedOutputAmount))
    expect(await token0.balanceOf(pair.address)).to.eq(token0Amount.add(swapAmount))
    expect(await token1.balanceOf(pair.address)).to.eq(token1Amount.sub(expectedOutputAmount))
    const totalSupplyToken0 = await token0.totalSupply()
    const totalSupplyToken1 = await token1.totalSupply()
    expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0.sub(token0Amount).sub(swapAmount))
    expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1.sub(token1Amount).add(expectedOutputAmount))

    console.log("price after:", (await orderBook.getPrice()).toString())
  })

 /* it('swap:limit order price == current price, amount > swap amount', async () => {
    console.log("price before:", (await orderBook.getPrice()).toString())

    console.log("base", tokenBase.address)
    console.log("quote", tokenQuote.address)
    console.log("token0", token0.address)
    console.log("token1", token1.address)

    await factory.setOrderBookFactory(orderBookFactory.address)
    console.log("orderBookFactory:", await factory.getOrderBookFactory(), "-", orderBookFactory.address)
    console.log("orderBook:", await orderBookFactory.getOrderBook(token0.address, token1.address))

    const limitAmount = expandTo18Decimals(3)
    await tokenQuote.transfer(orderBook.address, limitAmount)
    const limitPrice = expandTo18Decimals(2)
    await orderBook.createBuyLimitOrder(wallet.address, limitPrice, wallet.address, overrides)

    console.log("price after place order:", (await orderBook.getPrice()).toString())

    const reserves1 = await pair.getReserves()
    console.log("reserve0:", reserves1[0].toString())
    console.log("reserve1:", reserves1[1].toString())

    const reserves2 = await orderBook.getReserves()
    console.log("reserveBase:", reserves2[0].toString())
    console.log("reserveQuote:", reserves2[1].toString())

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = bigNumberify('2000000000000000000')

    //对于当前价格与挂单价格相等的情况，第一次getAmountForMovePrice的结果应该为0

    //sell base swapTo quote
    await token0.transfer(pair.address, swapAmount)
    await expect(pair.swap(0, expectedOutputAmount, wallet.address, '0x', overrides))
        .to.emit(token0, 'Transfer')
        .withArgs(pair.address, wallet.address, swapAmount)
    const tx = await pair.swap(0, expectedOutputAmount, wallet.address, '0x', overrides)
    const receipt = await tx.wait()
    console.log(receipt.gasUsed.toString())

    console.log("price after swap:", (await orderBook.getPrice()).toString())
  })*/

  /*
  it('swap:limit order price == current price, amount > swap amount', async () => {
    console.log("price before:", (await orderBook.getPrice()).toString())

    console.log("base", tokenBase.address)
    console.log("quote", tokenQuote.address)
    console.log("token0", token0.address)
    console.log("token1", token1.address)

    await factory.setOrderBookFactory(orderBookFactory.address)
    console.log("orderBookFactory:", await factory.getOrderBookFactory(), "-", orderBookFactory.address)
    console.log("orderBook:", await orderBookFactory.getOrderBook(token0.address, token1.address))

    const limitAmount = expandTo18Decimals(3)
    await tokenQuote.transfer(orderBook.address, limitAmount)
    const limitPrice = expandTo18Decimals(2)
    await orderBook.createBuyLimitOrder(wallet.address, limitPrice, wallet.address)

    console.log("price after place order:", (await orderBook.getPrice()).toString())

    const token0Amount = await token0.balanceOf(pair.address)
    const token1Amount = await token1.balanceOf(pair.address)
    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = bigNumberify('2000000000000000000')

    //sell base swapTo quote
    await token0.transfer(pair.address, swapAmount)
    await expect(pair.swap(0, expectedOutputAmount, wallet.address, '0x', overrides))
        .to.emit(token1, 'Transfer')
        .withArgs(pair.address, wallet.address, expectedOutputAmount)
        .to.emit(pair, 'Sync')
        .withArgs(token0Amount.add(swapAmount), token1Amount.sub(expectedOutputAmount))
        .to.emit(pair, 'Swap')
        .withArgs(wallet.address, swapAmount, 0, 0, expectedOutputAmount, wallet.address)

    const reserves = await pair.getReserves()
    expect(reserves[0]).to.eq(token0Amount.add(swapAmount))
    expect(reserves[1]).to.eq(token1Amount.sub(expectedOutputAmount))
    expect(await token0.balanceOf(pair.address)).to.eq(token0Amount.add(swapAmount))
    expect(await token1.balanceOf(pair.address)).to.eq(token1Amount.sub(expectedOutputAmount))
    const totalSupplyToken0 = await token0.totalSupply()
    const totalSupplyToken1 = await token1.totalSupply()
    expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0.sub(token0Amount).sub(swapAmount))
    expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1.sub(token1Amount).add(expectedOutputAmount))

    console.log("price after swap:", (await orderBook.getPrice()).toString())
  })
   */
})
