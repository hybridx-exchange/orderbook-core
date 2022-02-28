/*
import chai, {expect} from 'chai'
import {Contract} from 'ethers'
import {solidity, MockProvider, createFixtureLoader} from 'ethereum-waffle'

import {queuePriceFixture} from './shared/fixtures'

chai.use(solidity)

describe('HybridxOrderBook', () => {
    const provider = new MockProvider({
        hardfork: 'istanbul',
        mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
        gasLimit: 59999999
    })

    const [wallet, other] = provider.getWallets()
    const loadFixture = createFixtureLoader(provider, [wallet, other])

    let orderQueue: Contract
    let priceList: Contract

    beforeEach(async () => {
        const fixture = await loadFixture(queuePriceFixture)
        orderQueue = fixture.orderQueue
        priceList = fixture.priceList
    })

    const LIMIT_BUY = 1;
    const LIMIT_SELL = 2;

    /!*it('testOrderQueueLength', async () => {
        // @param 价格
        let price = 10000;
        // @expected 预期值
        let expected = 0;

        // @test 测试用例：测试订单队列的长度。预期值 0
        await expect(orderQueue.length(LIMIT_BUY, 10000)).to.eq({});
    })*!/

/!*    it('testOrderQueuePush', async () => {
        // @param 价格
        let price = 99;

        // @param 订单ID
        let data1 = 1;
        let data2 = 2;
        let data3 = 3;

        // @funcion
        await expect(orderQueue.push(LIMIT_BUY, price, data1))
        await expect(orderQueue.push(LIMIT_BUY, price, data2))
        await expect(orderQueue.push(LIMIT_BUY, price, data3))

        // @expected 预期值
        let expected = 3;

        // @test "测试用例：插入99价格3个订单，查询队列长度。预期值 3"
        await expect(orderQueue.length(1, 10000)).to.eq(3);
    })*!/
})
*/
