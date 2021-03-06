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

    async function pairInfo() {        // balance
        let pairTokenBase = await tokenBase.balanceOf(pair.address)
        console.log('pair Base tokenA balance:', pairTokenBase.toString())

        let pairTokenQuote = await tokenQuote.balanceOf(pair.address)
        console.log('pair Quote tokenB balance:', pairTokenQuote.toString())

        // K
        let [reserve0, reserve1] = await pair.getReserves()
        let k = reserve0 * reserve1
        console.log('pair K:', k.toString())

        // price
        let pairPrice = reserve1 / reserve0
        console.log('pair price:', pairPrice.toString())

        let pairPriceLibrary = await orderBook.getPrice()
        console.log('pair price Library:', pairPriceLibrary.toString())
    }

    async function getUserOrders() {
        let num = await orderBook.getUserOrders(wallet.address)
        let i = 1
        for (const o of num) {
            console.log('user orders:', i++)

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
        // pair balance
        let pairToken0Balance = await token0.balanceOf(pair.address)
        let pairToken1Balance = await token1.balanceOf(pair.address)
        console.log('pairToken0 balance:', pairToken0Balance.toString())
        console.log('pairToken1 balance:', pairToken1Balance.toString())

        let baseBalance = await orderBook.baseBalance();
        console.log('orderBook baseBalance:', baseBalance.toString())

        let quoteBalance = await orderBook.quoteBalance();
        console.log('orderBook quoteBalance:', quoteBalance.toString())

        let baseBalanceERC20 = await tokenBase.balanceOf(orderBook.address)
        console.log('orderBook baseBalance ERC20:', baseBalanceERC20.toString())

        let quoteBalanceERC20 = await tokenQuote.balanceOf(orderBook.address);
        console.log('orderBook quoteBalance ERC20:', quoteBalanceERC20.toString())

        let minAmount = await orderBook.minAmount();
        console.log('orderBook minAmount:', minAmount.toString())

        let priceStep = await orderBook.priceStep();
        console.log('orderBook priceStep:', priceStep.toString())

        let tokenBaseBalance = await tokenBase.balanceOf(wallet.address)
        let tokenQuoteBalance = await tokenQuote.balanceOf(wallet.address)
        console.log('wallet tokenBase Balance:', tokenBaseBalance.toString())
        console.log('wallet tokenQuote Balance:', tokenQuoteBalance.toString())
    }

    it('createBuyLimitOrder???require', async () => {
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(0), wallet.address))
            .to.be.revertedWith('Price Invalid')

        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.be.revertedWith('Amount Invalid')
    })

    it('createBuyLimitOrder???', async () => {
        console.log('?????????LP?????? = ????????????')
        // ?????????-???orderBook?????? ????????? ??????????????????OrderBook?????????1???????????????
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(1))
        // LP??????10/5=2??????????????????3?????????2???????????????2
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(1),
                bigNumberify('1000000000000000000'),
                expandTo18Decimals(2),
                LIMIT_BUY);
        // swap??????
        await getUserOrders()
    })

    it('createBuyLimitOrder???All Move Price', async () => {
        console.log('?????????????????????')
        // ?????????-???orderBook?????? ????????? ??????????????????OrderBook?????????1???????????????
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(2))
        // LP??????10/5=2??????????????????3?????????2???????????????2
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

        // swap??????
        await pairInfo()
    })

    it('createBuyLimitOrder???All Move Price - 0', async () => {
        console.log('?????????????????????')
        // ?????????-???orderBook?????? ????????? ??????????????????OrderBook?????????1???????????????
        await tokenQuote.transfer(orderBook.address, bigNumberify('2250825417403555361'))
        // LP??????10/5=2??????????????????3?????????2???????????????2
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

        // swap??????
        await pairInfo()
    })

    it('createBuyLimitOrder???Some Move Price', async () => {
        console.log('?????????????????????')
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(10))
        // LP??????10/5=2??????????????????3?????????10???????????????2250825417403555361
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(10),
                bigNumberify('7749174582596444639'),
                expandTo18Decimals(3),
                LIMIT_BUY);
        // swap??????
        await getUserOrders()
    })

    it('createBuyLimitOrder???More price', async () => {
        console.log('2->3^; ??????')
        // 2->3^; ??????
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(3))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(3),
                bigNumberify('749174582596444639'),
                expandTo18Decimals(3),
                LIMIT_BUY);

        console.log('3->5^; ??????')
        // 3->5^; ??????
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(5))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(5), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(5),
                bigNumberify('1429721486626979913'),
                expandTo18Decimals(5),
                LIMIT_BUY);

        console.log('5->6^; ??????')
        //  5->6^; ??????
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(6))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(6), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(6),
                bigNumberify('4487684293716986652'),
                expandTo18Decimals(6),
                LIMIT_BUY);
        // swap??????
        await getUserOrders()
    })

    it('Buy-Sell', async () => {
        console.log('?????????????????????????????????????????????')
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
                LIMIT_BUY)

        console.log('??????????????????????????????--????????????') // TODO revert
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(20))
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(20),
                bigNumberify('12940820234006285947'),
                expandTo18Decimals(1),
                LIMIT_SELL)

        await getUserOrders()
        await pairInfo()
    })

    // ????????? 2--6
    it('createBuyLimitOrder???price 2 -order-> 6', async () => {
        console.log('?????????????????????price 2 -order-> 6 ???????????????')
        // ??????????????????
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(1),
                bigNumberify('1000000000000000000'),
                expandTo18Decimals(3),
                LIMIT_SELL)

        await tokenBase.transfer(orderBook.address, expandTo18Decimals(2))
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(4), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(2),
                bigNumberify('2000000000000000000'),
                expandTo18Decimals(4),
                LIMIT_SELL)

        await tokenBase.transfer(orderBook.address, expandTo18Decimals(3))
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(5), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(3),
                bigNumberify('3000000000000000000'),
                expandTo18Decimals(5),
                LIMIT_SELL)
        await getUserOrders()

        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(50))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(6), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(50),
                bigNumberify('16746491169835059398'),
                expandTo18Decimals(6),
                LIMIT_BUY)
        await getUserOrders()
        await pairInfo()
    })

    // ???????????? 2--6
    it('createBuyLimitOrder???price 2 --> 6 ', async () => {
        console.log('?????????????????????price 2 --> 6 ???????????????')
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(50))
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(6), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(50),
                bigNumberify('42668491169835059398'),
                expandTo18Decimals(6),
                LIMIT_BUY)
        await getUserOrders()
        await pairInfo()
    })

    // SWAP - ORDERBOOK ????????????
    it('createBuyLimitOrder???SWAP - ORDERBOOK ', async () => {
        console.log('???????????????SWAP - ORDERBOOK: B - outB = A + inA')

        // [inA='xxx', A=5, B=10, outB=1] ?????????
        // B - outB = A + inA
        // 10 - 1 / xxx + 5

        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

        await balancePrint()
        await pairInfo()
        // 8337502084375521094
    })

    it('createBuyLimitOrder???Fee Rate', async () => {
        // 30/10000

        // ?????????-???orderBook?????? ????????? ??????????????????OrderBook?????????1???????????????
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(1))
        // LP??????10/5=2??????????????????3?????????2???????????????2
        await expect(orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(1),
                expandTo18Decimals(1),
                expandTo18Decimals(2),
                LIMIT_BUY)
        // swap??????
        await pairInfo()
        await balancePrint()

        // ??????
        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await expect(orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address))
            .to.emit(orderBook, 'OrderCreated')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(1),
                bigNumberify('501500000000000000'),
                expandTo18Decimals(2),
                LIMIT_SELL)

        await pairInfo()
        await balancePrint()
    })

})
