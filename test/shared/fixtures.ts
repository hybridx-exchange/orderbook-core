import { Contract, Wallet } from 'ethers'
import { Web3Provider } from 'ethers/providers'
import { deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './utilities'

import ERC20 from '@hybridx-exchange/v2-core/build/ERC20.json'
import UniswapV2Factory from '@hybridx-exchange/v2-core/build/UniswapV2Factory.json'
import UniswapV2Pair from '@hybridx-exchange/v2-core/build/UniswapV2Pair.json'
import OrderBookFactory from '../../build/OrderBookFactory.json'
import OrderBook from '../../build/OrderBookTest.json'
import WETH from '../../build/WETH9.json'

interface FactoryFixture {
  tokenA: Contract
  tokenB: Contract
  factory: Contract
  orderBookFactory: Contract
}

const overrides = {
  gasLimit: 9999999
}

export async function factoryFixture(_: Web3Provider, [wallet]: Wallet[]): Promise<FactoryFixture> {
  const tokenA = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)], overrides)
  const tokenB = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)], overrides)
  const factory = await deployContract(wallet, UniswapV2Factory, [wallet.address], overrides)
  const weth = await deployContract(wallet, WETH, [], overrides)
  const orderBookFactory = await deployContract(wallet, OrderBookFactory, [factory.address, weth.address], overrides)
  return { tokenA, tokenB, factory, orderBookFactory }
}

interface PairFixture extends FactoryFixture {
  token0: Contract
  token1: Contract
  pair: Contract
}

interface OrderBookFixture extends PairFixture {
  baseToken: Contract
  quoteToken: Contract
  orderBook: Contract
}

export async function orderBookFixture(provider: Web3Provider, [wallet]: Wallet[]): Promise<OrderBookFixture> {
  const { tokenA, tokenB, factory, orderBookFactory } = await factoryFixture(provider, [wallet])

  await factory.createPair(tokenA.address, tokenB.address, overrides)
  const pairAddress = await factory.getPair(tokenA.address, tokenB.address)
  const pair = new Contract(pairAddress, JSON.stringify(UniswapV2Pair.abi), provider).connect(wallet)

  const token0Address = await pair.token0()
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  await orderBookFactory.createOrderBook(tokenA.address, tokenB.address,
      expandTo18Decimals(1), expandTo18Decimals(1), overrides)
  const orderBookAddress = await orderBookFactory.getOrderBook(tokenA.address, tokenB.address)
  const orderBook = new Contract(orderBookAddress, JSON.stringify(OrderBook.abi), provider).connect(wallet)
  const baseToken = new Contract(await orderBook.baseToken(), JSON.stringify(ERC20.abi), provider).connect(wallet)
  const quoteToken = new Contract(await orderBook.quoteToken(), JSON.stringify(ERC20.abi), provider).connect(wallet)

  const token0Amount = expandTo18Decimals(5)
  const token1Amount = expandTo18Decimals(10)
  await token0.transfer(pair.address, token0Amount)
  await token1.transfer(pair.address, token1Amount)
  await pair.mint(wallet.address, overrides)

  return { factory, orderBookFactory, token0, token1, pair, baseToken, quoteToken, orderBook, tokenA, tokenB }
}
