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
        await getUserOrders()
    })*/

    /*it('createSellLimitOrder：All Move Price', async () => {
        console.log('卖单，全部吃单')
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(2))
        // 价格为1卖，数量2
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address)
        await pairInfo()
    })*/

    /*it('createSellLimitOrder：All Move Price - 0', async () => {
        console.log('卖单，临界吃单')
        await tokenBase.transfer(orderBook.address, bigNumberify('2074179765993714054'))
        // 价格为1卖，数量2
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address)
        await pairInfo()
    })*/

    /*it('createSellLimitOrder：Some Move Price', async () => {
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

        await getUserOrders()
    })*/

    // TODO 买卖结合：挂多个卖单、等待买单
    /*it('Sell-Buy', async () => {
        console.log('买卖结合：挂多个卖单、等待买单')
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(1),
                bigNumberify('1000000000000000000'),
                expandTo18Decimals(2),
                LIMIT_SELL);

        await tokenBase.transfer(orderBook.address, expandTo18Decimals(2))
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(2),
                bigNumberify('2000000000000000000'),
                expandTo18Decimals(3),
                LIMIT_SELL);

        await pairInfo()

        await tokenBase.transfer(orderBook.address, expandTo18Decimals(3))
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(3),
                bigNumberify('1000000000000000000'),
                expandTo18Decimals(1),
                LIMIT_SELL);

        await getUserOrders()

        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(10))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(10),
                bigNumberify('7925820234006285947'),
                expandTo18Decimals(1),
                LIMIT_BUY);
    })*/

    // SWAP - ORDERBOOK 误差测算
    /*it('createSellLimitOrder：SWAP - ORDERBOOK ', async () => {
        console.log('误差测算：SWAP - ORDERBOOK: B - outB = A + inA')

        // [inA=1, A=5, B=10, outB='1662497915624478906'] 原始有
        // B - outB = A + inA
        // 10 - 1662497915624478906 / 1 + 5

        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address)

        await balancePrint()
        await pairInfo()
        // 8337502084375521094
    })*/

    //  TODO 费率测试

})
