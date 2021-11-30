import chai, {expect} from 'chai'
import {Contract} from 'ethers'
import {solidity, MockProvider, createFixtureLoader} from 'ethereum-waffle'

import {expandTo18Decimals} from './shared/utilities'
import {orderBookFixture} from './shared/fixtures'

import {bigNumberify} from "ethers/utils";

chai.use(solidity)

let TEST_ADDRESSES: [string, string] = [
    '0x1000000000000000000000000000000000000000',
    '0x2000000000000000000000000000000000000000'
]

describe('HybridxOrderBook', () => {
    const provider = new MockProvider({
        hardfork: 'istanbul',
        mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
        gasLimit: 59999999
    })

    const TOTAL_SUPPLY = expandTo18Decimals(10000)

    const overrides = {
        gasLimit: 59999999
    }

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

    async function getUserOrders() {
        let num = await orderBook.getUserOrders(wallet.address)
        let i = 1
        for (const o of num) {
            console.log('user orders：', i++)

            let [a, b, c, d, e, f, g, h] = await orderBook.marketOrder(o)
            console.log('o.owner:', a.toString())
            console.log('o.to:', b.toString())
            console.log('o.orderId:', c.toString())
            console.log('o.price:', d.toString())
            console.log('o.amountOffer:', e.toString())
            console.log('o.amountRemain:', f.toString())
            console.log('o.orderType:', g.toString())
            console.log('o.orderIndex:', h.toString())
        }
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

        // 钱包余额
        let tokenBaseBalance = await tokenBase.balanceOf(wallet.address)
        let tokenQuoteBalance = await tokenQuote.balanceOf(wallet.address)
        console.log('wallet tokenBase Balance:', tokenBaseBalance.toString())
        console.log('wallet tokenQuote Balance:', tokenQuoteBalance.toString())
    }

    /*
    //取消订单：限价买订单
    it('cancelLimitOrder:BuyLimitOrder', async () => {
        // function (uint orderId)
        let orderId = await createBuyLimitOrder(3)
        console.log("order.orderId :", orderId.toString())
        let order = await orderBook.getUserOrders(wallet.address)
        printOrder(order)
        // 取消限价买订单
        await orderBook.cancelLimitOrder(orderId)
        let orderNull = await orderBook.getUserOrders(wallet.address)
        printOrder(orderNull)
    })

    //取消订单：限价卖订单
    it('cancelLimitOrder:SellLimitOrder', async () => {
        // function (uint orderId)
        let orderId = await createSellLimitOrder(2)
        console.log("order.orderId :", orderId.toString())
        let order = await orderBook.getUserOrders(wallet.address)
        printOrder(order)
        // 取消限价卖订单
        await orderBook.cancelLimitOrder(orderId)
        let orderNull = await orderBook.getUserOrders(wallet.address)
        printOrder(orderNull)
    })

    //用户订单
    it('userOrders', async () => {
        // function (address user, uint index)
        // 创建1个买单
        await createBuyLimitOrder(3)
        // 创建1个卖单
        await createSellLimitOrder(2)
        // function (address user, uint index)
        let orderId = await orderBook.userOrders(wallet.address, 0)
        console.log("order.orderId :", orderId.toString())

        let orderIdSell = await orderBook.userOrders(wallet.address, 1)
        console.log("order.orderIdSell :", orderIdSell.toString())
        // returns (uint orderId);
    })

    //市场订单
    it('marketOrder', async () => {
        // function (uint orderId)
        let orderId = await createBuyLimitOrder(3)

        console.log("market order:", await orderBook.marketOrder(orderId))

        //returns (uint[] memory order);
    })

    //市场订单薄
    it('marketBook', async () => {
        // function (uint direction, uint32 maxSize)

        console.log("market book LIMIT_BUY:", await orderBook.marketBook(LIMIT_BUY, 10))

        console.log("market book LIMIT_SELL:", await orderBook.marketBook(LIMIT_SELL, 10))
        // returns (uint[] memory prices, uint[] memory amounts);
    })

    //某个价格范围内的订单薄
    it('rangeBook', async () => {
        // function (uint direction, uint price)
        console.log("range book LIMIT_BUY:", await orderBook.rangeBook(LIMIT_BUY, 10))

        console.log("range book LIMIT_SELL:", await orderBook.rangeBook(LIMIT_SELL, 10))
        // returns (uint[] memory prices, uint[] memory amounts);
    })

    it('getPrice', async () => {
        // returns (uint price);
        console.log("range book LIMIT_BUY:", await orderBook.getPrice())
    })

    it('pair', async () => {
        console.log("pair:", await orderBook.pair())
        // returns (address);
    })

    //价格小数点位数
    it('priceDecimal', async () => {
        console.log("priceDecimal:", await orderBook.priceDecimal())
        // returns (uint);
    })

    //基准token -- 比如btc
    it('baseToken', async () => {
        console.log("baseToken:", await orderBook.baseToken())
        // returns (address);
    })

    //计价token -- 比如usd
    it('quoteToken', async () => {
        console.log("quoteToken:", await orderBook.quoteToken())
        // returns (address);
    })

    //价格间隔
    it('priceStep', async () => {
        console.log("priceStep:", await orderBook.priceStep())
        // returns (uint);
    })

    //更新价格间隔
    it('priceStepUpdate', async () => {
        console.log("priceStepUpdate:", await orderBook.priceStepUpdate())
        // function (uint newPriceStep)
    })

    //最小数量
    it('minAmount', async () => {
        console.log("minAmount:", await orderBook.minAmount())
    })

    //更新最小数量
    it('minAmountUpdate', async () => {
        console.log("minAmountUpdate:", await orderBook.minAmountUpdate())
        // function (uint newMinAmount)
    })

    it('getAmountOutForMovePrice', async () => {
        // function (address tokenIn, uint amountInOffer, uint reserveIn, uint reserveOut)

        let [amountOutGet, amountInLeft, reserveInRet, reserveOutRet] =
            await orderBook.getAmountOutForMovePrice(wallet.address, 0, 0, 0)

        expect(amountOutGet).to.eq(0)
        expect(amountInLeft).to.eq(0)
        expect(reserveInRet).to.eq(0)
        expect(reserveOutRet).to.eq(0)

        // returns (uint amountOutGet, uint amountInLeft, uint reserveInRet, uint reserveOutRet);
    })

    it('getAmountInForMovePrice', async () => {
        // function (address tokenOut, uint amountOutOffer, uint reserveIn, uint reserveOut)
        let [amountInGet, amountOutLeft, reserveInRet, reserveOutRet] =
            await orderBook.getAmountInForMovePrice(wallet.address, 0, 0, 0)

        expect(amountInGet).to.eq(0)
        expect(amountOutLeft).to.eq(0)
        expect(reserveInRet).to.eq(0)
        expect(reserveOutRet).to.eq(0)
        //returns (uint amountInGet, uint amountOutLeft, uint reserveInRet, uint reserveOutRet);
    })

    it('createOrderBook', async () => {
        // function (address tokenIn, uint amountIn, address to)
        console.log("createOrderBook:", await orderBook.getAmountInForMovePrice(wallet.address, 0, wallet.address))
        // returns (uint amountOutLeft, address[] memory accounts, uint[] memory amounts);
    })


    // 吃单：swap价格变动吃单
    // 吃单：orderBook挂买单，create全吃单
    // 吃单：orderBook挂买单，create部分吃单
    // 吃单：orderBook挂卖单，create全吃单
    // 吃单：orderBook挂卖单，create部分吃单
*/
})
