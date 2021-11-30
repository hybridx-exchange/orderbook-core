pragma solidity >=0.5.0;

import "../interfaces/IOrderBook.sol";
import "../interfaces/IOrderBookFactory.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "./SafeMath.sol";

library OrderBookLibrary {
    using SafeMath for uint;

    uint internal constant LIMIT_BUY = 1;
    uint internal constant LIMIT_SELL = 2;

    //根据价格计算使用amountIn换出的amountOut的数量
    function getAmountOutWithPrice(uint amountIn, uint price, uint decimal) internal pure returns (uint amountOut){
        amountOut = amountIn.mul(price) / 10 ** decimal;
    }

    //根据价格计算换出的amountOut需要使用amountIn的数量
    function getAmountInWithPrice(uint amountOut, uint price, uint decimal) internal pure returns (uint amountIn){
        amountIn = amountOut.mul(10 ** decimal) / price;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'OrderBookLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'OrderBookLibrary: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'OrderBookLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'OrderBookLibrary: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    //将价格移动到price需要消息的tokenA的数量, 以及新的reserveIn, reserveOut
    function getAmountForMovePrice(uint direction, uint reserveIn, uint reserveOut, uint price, uint decimal)
    internal pure returns (uint amountIn, uint amountOut, uint reserveInNew, uint reserveOutNew) {
        (uint baseReserve, uint quoteReserve) = (reserveIn, reserveOut);
        if (direction == LIMIT_BUY) {//buy (quoteToken == tokenA)  用tokenA换tokenB
            (baseReserve, quoteReserve) = (reserveOut, reserveIn);
            //根据p = y + (1-0.3%) * y' / (1-0.3%) * x 推出 997 * y' = (997 * x * p - 1000 * y), 如果等于0表示不需要移动价格
            //先计算997 * x * p
            uint b1 = getAmountOutWithPrice(baseReserve.mul(997), price, decimal);
            //再计算1000 * y
            uint q1 = quoteReserve.mul(1000);
            //再计算y' = (997 * x * p - 1000 * y) / 997
            amountIn = b1 > q1 ? (b1 - q1) / 997 : 0;
            //再计算x'
            amountOut = amountIn != 0 ? getAmountOut(amountIn, reserveIn, reserveOut) : 0;
            //再更新reserveInNew = reserveIn - x', reserveOutNew = reserveOut + y'
            (reserveInNew, reserveOutNew) = (reserveIn + amountIn, reserveOut - amountOut);
        }
        else if (direction == LIMIT_SELL) {//sell(quoteToken == tokenB) 用tokenA换tokenB
            //根据p = x + (1-0.3%) * x' / (1-0.3%) * y 推出 997 * x' = (997 * y * p - 1000 * x), 如果等于0表示不需要移动价格
            //先计算 y * p * 997
            uint q1 = getAmountOutWithPrice(quoteReserve.mul(997), price, decimal);
            //再计算 x * 1000
            uint b1 = baseReserve.mul(1000);
            //再计算x' = (997 * y * p - 1000 * x) / 997
            amountIn = q1 > b1 ? (q1 - b1) / 997 : 0;
            //再计算y' = (1-0.3%) x' / p
            amountOut = amountIn != 0 ? getAmountOut(amountIn, reserveIn, reserveOut) : 0;
            //再更新reserveInNew = reserveIn + x', reserveOutNew = reserveOut - y'
            (reserveInNew, reserveOutNew) = (reserveIn + amountIn, reserveOut - amountOut);
        }
        else {
            (amountIn, reserveInNew, reserveOutNew) = (0, reserveIn, reserveOut);
        }
    }

    //使用amountA数量的amountInOffer吃掉在价格price, 数量为amountOutOffer的tokenB, 返回实际消耗的tokenA数量和返回的tokenB的数量，amountOffer需要考虑手续费
    //手续费应该包含在amountOutWithFee中
    function getAmountOutForTakePrice(uint direction, uint amountInOffer, uint price, uint decimal, uint orderAmount)
    internal pure returns (uint amountIn, uint amountOutWithFee) {
        if (direction == LIMIT_BUY) { //buy (quoteToken == tokenIn)  用tokenIn（usdc)换tokenOut(btc)
            //amountOut = amountInOffer / price
            uint amountOut = getAmountOutWithPrice(amountInOffer, price, decimal);
            if (amountOut.mul(1000) <= orderAmount.mul(997)) { //只吃掉一部分: amountOut > amountOffer * (1-0.3%)
                (amountIn, amountOutWithFee) = (amountInOffer, amountOut);
            }
            else {
                uint amountOutWithoutFee = orderAmount.mul(997) / 1000;//吃掉所有
                //amountIn = amountOutWithoutFee * price
                (amountIn, amountOutWithFee) = (getAmountInWithPrice(amountOutWithoutFee, price, decimal),
                orderAmount);
            }
        }
        else if (direction == LIMIT_SELL) { //sell (quoteToken == tokenOut) 用tokenIn(btc)换tokenOut(usdc)
            //amountOut = amountInOffer * price
            uint amountOut = getAmountInWithPrice(amountInOffer, price, decimal);
            if (amountOut.mul(1000) <= orderAmount.mul(997)) { //只吃掉一部分: amountOut > amountOffer * (1-0.3%)
                (amountIn, amountOutWithFee) = (amountInOffer, amountOut);
            }
            else {
                uint amountOutWithoutFee = orderAmount.mul(997) / 1000;
                //amountIn = amountOutWithoutFee / price
                (amountIn, amountOutWithFee) = (getAmountOutWithPrice(amountOutWithoutFee, price,
                    decimal), orderAmount);
            }
        }
    }

    //期望获得amountOutExpect，需要投入多少amountIn
    function getAmountInForTakePrice(uint direction, uint amountOutExpect, uint price, uint decimal, uint orderAmount)
    internal pure returns (uint amountIn, uint amountOutWithFee) {
        if (direction == LIMIT_BUY) { //buy (quoteToken == tokenIn)  用tokenIn（usdc)换tokenOut(btc)
            uint amountOut = amountOutExpect.mul(997) / 1000;
            if (amountOut <= orderAmount) { //只吃掉一部分: amountOut > amountOffer * (1-0.3%)
                (amountIn, amountOutWithFee) = (getAmountOutWithPrice(amountOut, price, decimal), amountOutExpect);
            }
            else {
                uint amountOutWithoutFee = orderAmount.mul(997) / 1000;//吃掉所有
                //amountIn = amountOutWithoutFee * price
                (amountIn, amountOutWithFee) = (getAmountOutWithPrice(amountOutWithoutFee, price, decimal),
                orderAmount);
            }
        }
        else if (direction == LIMIT_SELL) { //sell (quoteToken == tokenOut) 用tokenIn(btc)换tokenOut(usdc)
            uint amountOut = amountOutExpect.mul(997) / 1000;
            if (amountOut <= orderAmount) { //只吃掉一部分: amountOut > amountOffer * (1-0.3%)
                (amountIn, amountOutWithFee) = (getAmountInWithPrice(amountOut, price, decimal), amountOutExpect);
            }
            else {
                uint amountOutWithoutFee = orderAmount.mul(997) / 1000;
                //amountIn = amountOutWithoutFee / price
                (amountIn, amountOutWithFee) = (getAmountInWithPrice(amountOutWithoutFee, price,
                    decimal), orderAmount);
            }
        }
    }
}