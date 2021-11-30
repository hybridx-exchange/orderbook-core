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

    /*it('createBuyLimitOrder：require', async () => {
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(0), wallet.address))
            .to.be.revertedWith('Hybridx OrderBook: Price Invalid')

        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.be.revertedWith('Hybridx OrderBook: Amount Invalid')
    })*/

    /*it('createBuyLimitOrder：LP.price = price', async () => {
        console.log('买单，LP价格 = 买单价格')
        // 挂买单-向orderBook中转 定价币 ：记价货币给OrderBook中转入1个计价货币
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(1))
        // LP价格10/5=2、挂买单价格3、数量2、吃掉全部2
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(1),
                bigNumberify('1000000000000000000'),
                expandTo18Decimals(2),
                LIMIT_BUY);
        // swap信息
        await getUserOrders()
    })*/

    /*it('createBuyLimitOrder：All Move Price', async () => {
        console.log('买单，全部吃单')
        // 挂买单-向orderBook中转 定价币 ：记价货币给OrderBook中转入1个计价货币
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(2))
        // LP价格10/5=2、挂买单价格3、数量2、吃掉全部2
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

        // swap信息
        await pairInfo()
    })*/

    /*it('createBuyLimitOrder：All Move Price - 0', async () => {
        console.log('买单，临界吃单')
        // 挂买单-向orderBook中转 定价币 ：记价货币给OrderBook中转入1个计价货币
        await tokenQuote.transfer(orderBook.address, bigNumberify('2250825417403555361'))
        // LP价格10/5=2、挂买单价格3、数量2、吃掉全部2
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

        // swap信息
        await pairInfo()
    })*/

    /*it('createBuyLimitOrder：Some Move Price', async () => {
        console.log('买单，部分吃单')
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(10))
        // LP价格10/5=2、挂买单价格3、数量10、吃掉部分2250825417403555361
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(10),
                bigNumberify('7749174582596444639'),
                expandTo18Decimals(3),
                LIMIT_BUY);
        // swap信息
        await getUserOrders()
    })*/

    /*it('createBuyLimitOrder：More price', async () => {
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
        await getUserOrders()
    })*/

    it('Buy-Sell', async () => {
        console.log('买卖结合：挂多个买单、等待卖单')
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(2))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(2),
                bigNumberify('2000000000000000000'),
                expandTo18Decimals(1),
                LIMIT_BUY);

        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(3))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(3),
                bigNumberify('3000000000000000000'),
                expandTo18Decimals(1),
                LIMIT_BUY);

        console.log('买卖结合：开始挂卖单--吃单买单') // TODO revert
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(20))
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(20),
                bigNumberify('20000000000000000000'),
                expandTo18Decimals(1),
                LIMIT_SELL);

        await getUserOrders()
        await pairInfo()
    })

    // 有买单 2--6
    /*it('createBuyLimitOrder：', async () => {
        // 添加几个买单
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(1))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(1),
                bigNumberify('749174582596444639'),
                expandTo18Decimals(3),
                LIMIT_BUY);

        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(2))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(4), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(2),
                bigNumberify('749174582596444639'),
                expandTo18Decimals(4),
                LIMIT_BUY);

        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(3))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(5), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(3),
                bigNumberify('749174582596444639'),
                expandTo18Decimals(5),
                LIMIT_BUY);

        await getUserOrders()
    })*/

    // 没有买单 2--6
    /*it('createBuyLimitOrder：', async () => {
        // 中间没有买单
    })*/

})
