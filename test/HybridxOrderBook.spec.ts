import chai, {expect} from 'chai'
import {Contract} from 'ethers'
import {solidity, MockProvider, createFixtureLoader} from 'ethereum-waffle'

import {expandTo18Decimals, printOrder} from './shared/utilities'
import {orderBookFixture} from './shared/fixtures'

import ERC20 from '@hybridx-exchange/v2-core/build/ERC20.json'
import UniswapV2Pair from '@hybridx-exchange/v2-core//build/UniswapV2Pair.json'
import OrderBook from '../build/OrderBook.json'
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
        // 1、deploy UniswapV2Factory [wallet.address]
        // 2、deploy WETH
        // 3、deploy OrderBookFactory [factory.address, weth.address]
        factory = fixture.factory
        token0 = fixture.token0
        token1 = fixture.token1
        // 创建货币对
        pair = fixture.pair
        // 创建货币对-成功之后
        // createOrderBook[tokenA, tokenB, bigNumberify("1000"), bigNumberify("1000")]
        orderBook = fixture.orderBook
        orderBookFactory = fixture.orderBookFactory
        // 基础货币
        tokenBase = fixture.tokenA
        // 计价货币
        tokenQuote = fixture.tokenB
        //
        await factory.setOrderBookFactory(orderBookFactory.address);
    })

    // tokenA.balance = 10000 、 tokenB.balance = 10000
    // transfer(pair.address) token0-5=9995 、 token1-10=9990
    //
    // createOrderBook() tokenA tokenB priceStep=1000 minAmount=1000

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
        let [o] = await orderBook.getUserOrders(wallet.address);
        console.log('user orders id：', o.toString())

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

    /*it('createBuyLimitOrder：require', async () => {
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(0), wallet.address))
            .to.be.revertedWith('Hybridx OrderBook: Price Invalid')

        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.be.revertedWith('Hybridx OrderBook: Amount Invalid')
    })*/

    it('createBuyLimitOrder：All Move Price', async () => {
        // swap信息
        await pairInfo()

        console.log('买单，全部吃单')
        // 挂买单-向orderBook中转 定价币 ：记价货币给OrderBook中转入1个计价货币
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(2))
        // LP价格10/5=2、挂买单价格3、数量2、吃掉全部2
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

        // swap信息
        await pairInfo()
    })

    /*it('createBuyLimitOrder：Some Move Price', async () => {
        console.log('买单，部分吃单')
        // 余额信息
        await balancePrint()
        // swap信息
        await pairInfo()

        // 挂买单-向orderBook中转 定价币 ：记价货币给OrderBook中转入1个计价货币
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(10))

        /!* LP价格10/5=2、挂买单价格3、数量10、吃掉部分2250825417403555361 *!/
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(10),
                bigNumberify('7749174582596444639'),
                expandTo18Decimals(3),
                LIMIT_BUY);

        // 订单信息
        await getUserOrders()
        // swap信息
        await pairInfo()
        // 余额信息
        await balancePrint()
    })*/

    /*it('createBuyLimitOrder：More price', async () => {
        // 余额信息
        await balancePrint()
        // swap信息
        await pairInfo()

        console.log('2->3^; 挂单')
        // 2->3^; 挂单
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(3))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(3),
                bigNumberify('749174582596444639'),
                expandTo18Decimals(3),
                LIMIT_BUY);
        // swap信息
        await pairInfo()

        console.log('3->5^; 挂单')
        // 3->5^; 挂单
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(5))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(5), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(5),
                bigNumberify('1429721486626979913'),
                expandTo18Decimals(5),
                LIMIT_BUY);
        // swap信息
        await pairInfo()

        console.log('5->6^; 挂单')
       //  5->6^; 挂单
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(6))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(6), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(6),
                bigNumberify('4487684293716986652'),
                expandTo18Decimals(6),
                LIMIT_BUY);
        // swap信息
        await pairInfo()
    })*/

    // TODO 买卖结合

    //创建限价卖订单
    /*it('createSellLimitOrder：require', async () => {
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(0), wallet.address))
            .to.be.revertedWith('Hybridx OrderBook: Price Invalid')

        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.be.revertedWith('Hybridx OrderBook: Amount Invalid')
    })*/

    /*it('createSellLimitOrder：create', async () => {
        console.log('卖单，挂一个单')
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(1),
                bigNumberify('1000000000000000000'),
                expandTo18Decimals(2),
                LIMIT_SELL);

        await pairInfo()
        await getUserOrders()
    })*/

    it('createSellLimitOrder：All Move Price', async () => {
        await pairInfo()
        console.log('卖单，全部吃单')
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(2))
        // 价格为1卖，数量2
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address))
        await pairInfo()
    })

    it('createSellLimitOrder：All Move Price - 0', async () => {
        await pairInfo()
        console.log('卖单，临界吃单')
        await tokenBase.transfer(orderBook.address, bigNumberify('2074179765993714054'))
        // 价格为1卖，数量2
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address))
        await pairInfo()
    })

    it('createSellLimitOrder：Some Move Price', async () => {
        await pairInfo()
        console.log('卖单，部分吃单')
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(10))
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(10),
                bigNumberify('7925820234006285947'),
                expandTo18Decimals(1),
                LIMIT_SELL);

        await pairInfo()
        await getUserOrders()
    })

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
