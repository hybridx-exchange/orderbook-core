import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { AddressZero } from 'ethers/constants'
import { bigNumberify } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'

import {expandTo18Decimals, getCreate2Address} from './shared/utilities'
import { factoryFixture } from './shared/fixtures'

import ERC20 from '@hybridx-exchange/v2-core/build/ERC20.json'
import UniswapV2Pair from '@hybridx-exchange/v2-core//build/UniswapV2Pair.json'
import OrderBook from '../build/OrderBook.json'

chai.use(solidity)

let TEST_ADDRESSES: [string, string] = [
  '0x1000000000000000000000000000000000000000',
  '0x2000000000000000000000000000000000000000'
]

describe('HybridxOrderBookFactory', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })

  const overrides = {
    gasLimit: 9999999
  }

  const [wallet, other] = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, [wallet, other])

  let factory: Contract
  let orderBookFactory: Contract
  beforeEach(async () => {
    const fixture = await loadFixture(factoryFixture)
    factory = fixture.factory
    orderBookFactory = fixture.orderBookFactory
    //由于初始化时调用了ERC20的接口，所以需要创建ERC20合约后才能创建orderbook
    TEST_ADDRESSES[0] = fixture.tokenA.address < fixture.tokenB.address ? fixture.tokenA.address : fixture.tokenB.address
    TEST_ADDRESSES[1] = fixture.tokenA.address > fixture.tokenB.address ? fixture.tokenA.address : fixture.tokenB.address
  })

  it('feeTo, admin, allPairsLength', async () => {
    expect(await factory.feeTo()).to.eq(AddressZero)
    expect(await factory.admin()).to.eq(wallet.address)
    expect(await factory.allPairsLength()).to.eq(0)
  })

  async function createPair(tokens: [string, string]) : Promise<String> {
    const bytecode = `0x${UniswapV2Pair.evm.bytecode.object}`
    const create2Address = getCreate2Address(factory.address, tokens, bytecode)
    await expect(factory.createPair(...tokens))
      .to.emit(factory, 'PairCreated')
      .withArgs(TEST_ADDRESSES[0], TEST_ADDRESSES[1], create2Address, bigNumberify(1))

    await expect(factory.createPair(...tokens)).to.be.reverted // UniswapV2: PAIR_EXISTS
    await expect(factory.createPair(...tokens.slice().reverse())).to.be.reverted // UniswapV2: PAIR_EXISTS
    expect(await factory.getPair(...tokens)).to.eq(create2Address)
    expect(await factory.getPair(...tokens.slice().reverse())).to.eq(create2Address)
    expect(await factory.allPairs(0)).to.eq(create2Address)
    expect(await factory.allPairsLength()).to.eq(1)

    const pair = new Contract(create2Address, JSON.stringify(UniswapV2Pair.abi), provider)
    expect(await pair.factory()).to.eq(factory.address)
    expect(await pair.token0()).to.eq(TEST_ADDRESSES[0])
    expect(await pair.token1()).to.eq(TEST_ADDRESSES[1])

    return pair.address
  }

  async function createOrderBook(tokens: [string, string]) {
    await factory.createPair(...tokens)
    const pairAddress = await factory.getPair(...tokens)
    const bytecode = `0x${OrderBook.evm.bytecode.object}`
    const create2Address = getCreate2Address(orderBookFactory.address, tokens, bytecode)

    await expect(orderBookFactory.createOrderBook(...tokens, expandTo18Decimals(1), expandTo18Decimals(2), overrides))
        .to.emit(orderBookFactory, 'OrderBookCreated')
        .withArgs(pairAddress, ...tokens, create2Address, expandTo18Decimals(1), expandTo18Decimals(2))

    await expect(orderBookFactory.createOrderBook(...tokens,
        expandTo18Decimals(1), expandTo18Decimals(2))).to.be.reverted // UniswapV2: PAIR_EXISTS
    await expect(orderBookFactory.createOrderBook(...tokens.slice().reverse(),
        expandTo18Decimals(1), expandTo18Decimals(2))).to.be.reverted // UniswapV2:// PAIR_EXISTS
    expect(await orderBookFactory.getOrderBook(...tokens)).to.eq(create2Address)
    expect(await orderBookFactory.getOrderBook(...tokens.slice().reverse())).to.eq(create2Address)
    expect(await orderBookFactory.allOrderBooks(0)).to.eq(create2Address)
    expect(await orderBookFactory.allOrderBookLength()).to.eq(1)

    const orderBook = new Contract(create2Address, JSON.stringify(OrderBook.abi), provider)
    expect(await orderBook.factory()).to.eq(orderBookFactory.address)
    expect(await orderBook.pair()).to.eq(pairAddress)

    const quoteToken = new Contract(await orderBook.quoteToken(), JSON.stringify(ERC20.abi), provider)
    expect(await orderBook.priceDecimal()).to.eq(await quoteToken.decimals())
  }

  it('createOrderBook', async () => {
    await createOrderBook(TEST_ADDRESSES)
  })

  it('createOrderBook:reverse', async () => {
    await createOrderBook(TEST_ADDRESSES.slice().reverse() as [string, string])
  })
})
