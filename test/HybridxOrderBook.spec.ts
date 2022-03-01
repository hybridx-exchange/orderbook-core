import chai, {expect} from 'chai'
import {Contract} from 'ethers'
import {solidity, MockProvider, createFixtureLoader} from 'ethereum-waffle'

import {expandTo18Decimals, printOrder} from './shared/utilities'
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

    it('cancelLimitOrder: one order', async () => {
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(3))
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address)

        let orderIdBuy = await orderBook.getUserOrders(wallet.address)

        await expect(orderBook.cancelLimitOrder(orderIdBuy))
            .to.emit(orderBook, 'OrderCanceled')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(3),
                bigNumberify('3000000000000000000'),
                expandTo18Decimals(1),
                LIMIT_BUY);

        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

        let orderIdSell = await orderBook.getUserOrders(wallet.address)

        await expect(orderBook.cancelLimitOrder(orderIdSell))
            .to.emit(orderBook, 'OrderCanceled')
            .withArgs(wallet.address,
                wallet.address,
                expandTo18Decimals(1),
                bigNumberify('1000000000000000000'),
                expandTo18Decimals(3),
                LIMIT_SELL);
    })

    it('userOrders', async () => {
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(3))
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address)

        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

        expect(await orderBook.userOrders(wallet.address, 0)).to.eq(1);
        expect(await orderBook.userOrders(wallet.address, 1)).to.eq(2);
    })

    it('marketOrder', async () => {
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(3))
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

        await getUserOrders()
    })

    it('marketBook', async () => {
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address)
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(1), wallet.address)

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

        //console.log("market book LIMIT_BUY:", await orderBook.marketBook(LIMIT_BUY, 10))
        let [prices, amounts] = await orderBook.marketBook(LIMIT_BUY, 10)
        await printPricesAmounts('LIMIT_BUY', prices, amounts)

        //console.log("market book LIMIT_SELL:", await orderBook.marketBook(LIMIT_SELL, 10))
        let [ps, as] = await orderBook.marketBook(LIMIT_SELL, 10)
        await printPricesAmounts('LIMIT_SELL', ps, as)

        console.log("rangeBook TEST:")
        let [rangePrices, rangeAmounts] = await orderBook.rangeBook(LIMIT_BUY, 1)
        await printPricesAmounts('rangeBook LIMIT_BUY', rangePrices, rangeAmounts)

        let [rps, ras] = await orderBook.rangeBook(LIMIT_SELL, 10)
        await printPricesAmounts('rangeBook LIMIT_SELL', rps, ras)
    })

    async function printPricesAmounts(limit: string, prices: [number], amounts: [number]) {
        for (const p of prices) {
            console.log(limit, ' price:', p.toString())
        }
        for (const a of amounts) {
            console.log(limit, ' amount:', a.toString())
        }
    }

    it('getPrice', async () => {
        await tokenQuote.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createBuyLimitOrder(wallet.address, expandTo18Decimals(2), wallet.address)

        await tokenBase.transfer(orderBook.address, expandTo18Decimals(1))
        await orderBook.createSellLimitOrder(wallet.address, expandTo18Decimals(3), wallet.address)

        expect(await orderBook.getPrice()).to.eq(expandTo18Decimals(2))
    })

    it('pair', async () => {
        expect(await orderBook.pair()).to.eq('0x4d561Eb2278c59AEd5669FaD2d9b5F735d9cf5B4')
    })

    it('priceDecimal', async () => {
        let priceDecimal = await orderBook.priceDecimal()
        expect(await orderBook.priceDecimal()).to.eq(18)
    })

    it('protocolFeeRate', async () => {
        expect(await orderBook.protocolFeeRate()).to.eq(30)
    })

    it('subsidyFeeRate', async () => {
        expect(await orderBook.subsidyFeeRate()).to.eq(50)
    })

    it('baseToken', async () => {
        expect(await orderBook.baseToken()).to.eq('0xA193E42526F1FEA8C99AF609dcEabf30C1c29fAA')
    })

    it('quoteToken', async () => {
        expect(await orderBook.quoteToken()).to.eq('0xFDFEF9D10d929cB3905C71400ce6be1990EA0F34')
    })

    it('priceStep', async () => {
        expect(await orderBook.priceStep()).to.eq(1000)
    })

    it('priceStepUpdate', async () => {
        await orderBook.priceStepUpdate(100)
        expect(await orderBook.priceStep()).to.eq(100)
    })

    it('minAmount', async () => {
        expect(await orderBook.minAmount()).to.eq(1000)
    })

    it('minAmountUpdate', async () => {
        await orderBook.minAmountUpdate(100)
        expect(await orderBook.minAmount()).to.eq(100)
    })

    it('protocolFeeRateUpdate', async () => {
        await expect(orderBook.connect(other).protocolFeeRateUpdate(10))
            .to.be.revertedWith('Forbidden')

        await orderBook.connect(wallet).protocolFeeRateUpdate(10)
        expect(await orderBook.protocolFeeRate()).to.eq(10)
    })

    it('subsidyFeeRateUpdate', async () => {
        await expect(orderBook.connect(other).subsidyFeeRateUpdate(10))
            .to.be.revertedWith('Forbidden')

        await orderBook.connect(wallet).subsidyFeeRateUpdate(10)
        expect(await orderBook.subsidyFeeRate()).to.eq(10)
    })

    it('getAmountOutForMovePrice', async () => {
        expect(await orderBook.getAmountOutForMovePrice(tokenBase.address, 0)).to.eq(0)
        expect(await orderBook.getAmountOutForMovePrice(tokenBase.address, 10)).to.eq(19)
        expect(await orderBook.getAmountOutForMovePrice(tokenBase.address, expandTo18Decimals(10)))
            .to.eq(bigNumberify('6659986639946559786'))

        expect(await orderBook.getAmountOutForMovePrice(tokenQuote.address, 0)).to.eq(0)
        expect(await orderBook.getAmountOutForMovePrice(tokenQuote.address, 10)).to.eq(4)
        expect(await orderBook.getAmountOutForMovePrice(tokenQuote.address, expandTo18Decimals(10)))
            .to.eq(bigNumberify('2496244366549824737'))
    })

    it('getAmountInForMovePrice', async () => {
        expect(await orderBook.getAmountInForMovePrice(tokenBase.address, 0)).to.eq(0)
        expect(await orderBook.getAmountInForMovePrice(tokenBase.address, 10)).to.eq(21)
        expect(await orderBook.getAmountInForMovePrice(tokenBase.address, bigNumberify('2496244366549824737')))
            .to.eq(expandTo18Decimals(10))

        expect(await orderBook.getAmountInForMovePrice(tokenQuote.address, 0)).to.eq(0)
        expect(await orderBook.getAmountInForMovePrice(tokenQuote.address, 10)).to.eq(6)
        expect(await orderBook.getAmountInForMovePrice(tokenQuote.address, bigNumberify('6659986639946559786')))
            .to.eq(bigNumberify('9999999999999999999'))
    })
})
