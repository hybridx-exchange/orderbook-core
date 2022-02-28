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

    //取消订单：限价买订单 TODO 取消订单测试失败
    /*it('cancelLimitOrder: one order', async () => {
        await transferToOther()

        // 创建买单
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(3))
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)
        // 获取订单ID
        let orderIdBuy = await orderBook.getUserOrders(wallet.address)
        // 取消限价买订单
        await expect(orderBook.cancelLimitOrder(orderIdBuy))
            .to.emit(orderBook, 'OrderCanceled')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(3),
                bigNumberify('749174582596444639'),
                expandTo18Decimals(3),
                LIMIT_BUY);
        await getOrdersById(orderIdBuy)

        // 创建卖单
        await tokenBase.connect(other).transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.connect(other).createSellLimitOrder(other.address, expandTo18Decimals(3), other.address)
        // 获取订单ID
        let orderIdSell = await orderBook.getUserOrders(other.address)
        // 取消限价买订单
        await expect(orderBook.connect(other).cancelLimitOrder(orderIdSell))
            .to.emit(orderBook, 'OrderCanceled')
            .withArgs(other.address,
                other.address,
                expandTo18Decimals(1),
                bigNumberify('1000000000000000000'),
                expandTo18Decimals(3),
                LIMIT_SELL);
    })*/

    // 用户订单
    /*it('userOrders', async () => {
        await transferToOther()

        // 创建1个买单
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(3))
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)
        expect(await orderBook.userOrders(wallet.address, 0)).to.eq(1)

        // 创建1个卖单
        await tokenBase.connect(other).transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.connect(other).createSellLimitOrder(other.address, expandTo18Decimals(3), other.address)
        expect(await orderBook.userOrders(other.address, 0)).to.eq(1)
    })*/

    // 市场订单
    /*it('marketOrder', async () => {
        await transferToOther()

        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(3))
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

        await tokenBase.connect(other).transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.connect(other).createSellLimitOrder(other.address, expandTo18Decimals(3), other.address)

        await getWalletOrders()
        await getOtherOrders()
    })*/

    //市场订单薄
    /*it('marketBook、rangeBook', async () => {
        await transferToOther()

        // 2个买单
        await tokenQuote.connect(other).transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.connect(other).createBuyLimitOrder(other.address, expandTo18Decimals(2), other.address)
        await tokenQuote.connect(other).transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.connect(other).createBuyLimitOrder(other.address, expandTo18Decimals(1), other.address)
        // 10个卖单
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(4), wallet.address)
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(5), wallet.address)
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(6), wallet.address)
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(7), wallet.address)
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(8), wallet.address)
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(9), wallet.address)
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(10), wallet.address)
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(11), wallet.address)
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(12), wallet.address)
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(13), wallet.address)
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(14), wallet.address)
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(15), wallet.address)

        //订单个数
        let [prices, amounts] = await orderBook.marketBook(LIMIT_BUY, 10)
        await printPricesAmounts('LIMIT_BUY', prices, amounts)

        let [ps, as] = await orderBook.marketBook(LIMIT_SELL, 10)
        await printPricesAmounts('LIMIT_SELL', ps, as)

        //某个价格范围内的订单薄
        console.log("rangeBook TEST:")
        let [rangePrices, rangeAmounts] = await orderBook.rangeBook(LIMIT_BUY, expandTo18Decimals(1))
        await printPricesAmounts('rangeBook LIMIT_BUY', rangePrices, rangeAmounts)

        let [rps, ras] = await orderBook.rangeBook(LIMIT_SELL, expandTo18Decimals(10))
        await printPricesAmounts('rangeBook LIMIT_SELL', rps, ras)
    })*/

    async function printPricesAmounts(limit: string, prices: [number], amounts: [number]) {
        for (const p of prices) {
            console.log(limit, ' price:', p.toString())
        }
        for (const a of amounts) {
            console.log(limit, ' amount:', a.toString())
        }
    }

    /*it('getPrice', async () => {
        await transferToOther()

        // 1个买单
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address)
        // 1个卖单
        await tokenBase.connect(other).transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.connect(other).createSellLimitOrder(other.address, expandTo18Decimals(3), other.address)

        let price = await orderBook.getPrice()
        console.log("get price:", price.toString())
    })*/

    // 统计：下单、吃单 gas费用
    //
    // 有吃单的情况
    // 没有吃单的情况
    //
    // 下多个单的情况
    // 吃多个单的情况
    //
    // gas费用
})
