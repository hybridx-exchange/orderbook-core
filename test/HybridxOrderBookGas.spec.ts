import chai, {expect} from 'chai'
import {Contract} from 'ethers'
import {solidity, MockProvider, createFixtureLoader} from 'ethereum-waffle'

import {expandTo18Decimals, printOrder} from './shared/utilities'
import {orderBookFixture} from './shared/fixtures'

import {bigNumberify} from "ethers/utils";

chai.use(solidity)

describe('HybridxOrderBook', () => {
    const provider = new MockProvider({
        hardfork: 'istanbul',
        mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
        gasLimit: 59999999
    })

    const LIMIT_BUY = 1;
    const LIMIT_SELL = 2;

    const [wallet, other] = provider.getWallets()
    const loadFixture = createFixtureLoader(provider, [wallet, other])

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
        await factory.setOrderBookFactory(orderBookFactory.address);
    })

    async function pairInfo() {
        // balance
        let pairTokenBase = await tokenBase.balanceOf(pair.address)
        console.log('pair Base tokenA balance：', pairTokenBase.toString())

        let pairTokenQuote = await tokenQuote.balanceOf(pair.address)
        console.log('pair Quote tokenB balance：', pairTokenQuote.toString())

        // K
        let [reserve0, reserve1] = await pair.getReserves()
        let k = reserve0 * reserve1
        console.log('pair K：', k.toString())

        // 价格
        let pairPrice = reserve1 / reserve0
        console.log('pair price：', pairPrice.toString())

        let pairPriceLibrary = await orderBook.getPrice()
        console.log('pair price Library：', pairPriceLibrary.toString())
    }

    async function getWalletOrders() {
        let num = await orderBook.getUserOrders(wallet.address)
        let i = 1
        for (const o of num) {
            console.log('user orders：', i++)
            getOrdersById(o)
        }
    }

    async function getOtherOrders() {
        let num = await orderBook.getUserOrders(other.address)
        let i = 1
        for (const o of num) {
            console.log('other orders：', i++)
            getOrdersById(o)
        }
    }

    async function getOrdersById(o: any) {
        let [a, b, c, d, e, f, g, h] = await orderBook.marketOrder(o)
        console.log('order.owner:', a.toString())
        console.log('order.to:', b.toString())
        console.log('order.orderId:', c.toString())
        console.log('order.price:', d.toString())
        console.log('order.amountOffer:', e.toString())
        console.log('order.amountRemain:', f.toString())
        console.log('order.orderType:', g.toString())
        console.log('order.orderIndex:', h.toString())
    }

    async function balancePrint() {
        // pair余额
        let pairToken0Balance = await token0.balanceOf(pair.address)
        let pairToken1Balance = await token1.balanceOf(pair.address)
        console.log('pairToken0 balance：', pairToken0Balance.toString())
        console.log('pairToken1 balance：', pairToken1Balance.toString())

        // orderBook配置
        let baseBalance = await orderBook.baseBalance();
        console.log('orderBook baseBalance：', baseBalance.toString())

        let quoteBalance = await orderBook.quoteBalance();
        console.log('orderBook quoteBalance：', quoteBalance.toString())

        let baseBalanceERC20 = await tokenBase.balanceOf(orderBook.address)
        console.log('orderBook baseBalance ERC20：', baseBalanceERC20.toString())

        let quoteBalanceERC20 = await tokenQuote.balanceOf(orderBook.address);
        console.log('orderBook quoteBalance ERC20：', quoteBalanceERC20.toString())

        let minAmount = await orderBook.minAmount();
        console.log('orderBook minAmount：', minAmount.toString())

        let priceStep = await orderBook.priceStep();
        console.log('orderBook priceStep：', priceStep.toString())

        // wallet 钱包余额
        let tokenBaseBalance = await tokenBase.balanceOf(wallet.address)
        let tokenQuoteBalance = await tokenQuote.balanceOf(wallet.address)
        console.log('wallet tokenBase Balance:', tokenBaseBalance.toString())
        console.log('wallet tokenQuote Balance:', tokenQuoteBalance.toString())

        // other 钱包余额
        let otherTokenBaseBalance = await tokenBase.balanceOf(other.address)
        let otherTokenQuoteBalance = await tokenQuote.balanceOf(other.address)
        console.log('other tokenBase Balance:', otherTokenBaseBalance.toString())
        console.log('other tokenQuote Balance:', otherTokenQuoteBalance.toString())
    }

    async function transferToOther() {
        await tokenQuote.transfer(other.address, expandTo18Decimals(20000))
        await tokenBase.transfer(other.address, expandTo18Decimals(20000))
    }

    // 统计：下单、吃单 gas费用
    // 有吃单的情况
    // 没有吃单的情况
    // 下多个单的情况
    // 吃多个单的情况
    // gas费用

    // 下买单GAS
    it('', async () => {
        // 下单
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address)
        // 查看余额
        // print
        // 取消订单

        // 查看余额
    })
    // 下卖单GAS
    it('', async () => {

    })
    // 下卖单-吃单GAS
    it('', async () => {

    })
    // 下买单-吃单GAS
    it('', async () => {

    })
    // 下多个卖单-吃单GAS
    it('', async () => {

    })
    // 下多个买单-吃单GAS
    it('', async () => {

    })
    // 下多个卖单-吃多个单GAS
    it('', async () => {

    })
    // 下多个买单-吃多个单GAS
    it('', async () => {

    })

})
