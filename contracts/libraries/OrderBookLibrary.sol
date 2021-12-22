pragma solidity >=0.5.0;

import "../interfaces/IOrderBook.sol";
import "../interfaces/IOrderBookFactory.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "./Math.sol";
import "./SafeMath.sol";

library OrderBookLibrary {
    using SafeMath for uint;

    uint internal constant LIMIT_BUY = 1;
    uint internal constant LIMIT_SELL = 2;

    function getOppositeDirection(uint direction) internal pure returns (uint opposite){
        if (LIMIT_BUY == direction) {
            opposite = LIMIT_SELL;
        }
        else if (LIMIT_SELL == direction) {
            opposite = LIMIT_BUY;
        }
    }

    //get buy amount with price based on price and offered amount
    function getBuyAmountWithPrice(uint amountOffer, uint price, uint decimal) internal pure returns (uint amountGet){
        amountGet = amountOffer.mul(10 ** decimal).div(price);
    }

    //get sell amount with price based on price and offered amount
    function getSellAmountWithPrice(uint amountOffer, uint price, uint decimal) internal pure returns (uint amountGet){
        amountGet = amountOffer.mul(price).div(10 ** decimal);
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

    // fetches and sorts the reserves for a pair
    function getReserves(address pair, address tokenA, address tokenB) internal view returns
    (uint112 reserveA, uint112 reserveB) {
        require(tokenA != tokenB, 'OrderBookLibrary: IDENTICAL_ADDRESSES');
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        require(token0 != address(0), 'OrderBookLibrary: ZERO_ADDRESS');
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getPrice(uint reserveBase, uint reserveQuote, uint decimal) internal pure returns (uint price){
        if (reserveBase != 0) {
            uint d = reserveQuote.mul(10 ** decimal);
            price = d / reserveBase;
        }
    }

    function getFixAmountForMovePriceUp(uint _amountLeft, uint _amountAmmQuote,
        uint reserveBase, uint reserveQuote, uint targetPrice, uint priceDecimal)
    internal pure returns (uint amountLeft, uint amountAmmQuote) {
        uint curPrice = getPrice(reserveBase, reserveQuote, priceDecimal);
        //弥补精度损失造成的LP价格误差，将LP的价格提高一点，保证买单价格小于或等于LP价格
        //y' = x.p2 - x.p1, x不变，增加y, 使用价格变大
        if (curPrice < targetPrice) {
            uint amountQuoteFix = (reserveBase.mul(targetPrice).div(10 ** priceDecimal)
            .sub(reserveBase.mul(curPrice).div(10 ** priceDecimal)));
            amountQuoteFix = amountQuoteFix > 0 ? amountQuoteFix : 1;
            require(_amountLeft >= amountQuoteFix, "Hybridx OrderBook: Not Enough Output Amount");
            (amountLeft, amountAmmQuote) = (_amountLeft.sub(amountQuoteFix), _amountAmmQuote + amountQuoteFix);
        }
        else {
            (amountLeft, amountAmmQuote) = (_amountLeft, _amountAmmQuote);
        }
    }

    function getFixAmountForMovePriceDown(uint _amountLeft, uint _amountAmmBase,
        uint reserveBase, uint reserveQuote, uint targetPrice, uint priceDecimal)
    internal pure returns (uint amountLeft, uint amountAmmBase) {
        uint curPrice = getPrice(reserveBase, reserveQuote, priceDecimal);
        //弥补精度损失造成的LP价格误差，将LP的价格降低一点，保证订单价格大于或等于LP价格
        //x' = y/p1 - y/p2, y不变，增加x，使价格变小
        if (curPrice > targetPrice) {
            uint amountBaseFix = (reserveQuote.mul(10 ** priceDecimal).div(targetPrice)
            .sub(reserveQuote.mul(10 ** priceDecimal).div(curPrice)));
            amountBaseFix = amountBaseFix > 0 ? amountBaseFix : 1;
            require(_amountLeft >= amountBaseFix, "Hybridx OrderBook: Not Enough Input Amount");
            (amountLeft, amountAmmBase) = (_amountLeft.sub(amountBaseFix), _amountAmmBase + amountBaseFix);
        }
        else {
            (amountLeft, amountAmmBase) = (_amountLeft, _amountAmmBase);
        }
    }

    //sqrt(9*y*y + 3988000*x*y*price)
    function getSection1ForPriceUp(uint reserveIn, uint reserveOut, uint price, uint decimal)
    internal
    pure
    returns (uint section1) {
        section1 = Math.sqrt(reserveOut.mul(reserveOut).mul(9).add(reserveIn.mul(reserveOut).mul(3988000).mul
        (price).div(10**decimal)));
    }

    //sqrt(9*x*x + 3988000*x*y/price)
    function getSection1ForPriceDown(uint reserveIn, uint reserveOut, uint price, uint decimal)
    internal
    pure
    returns (uint section1) {
        section1 = Math.sqrt(reserveIn.mul(reserveIn).mul(9).add(reserveIn.mul(reserveOut).mul(3988000).mul
        (10**decimal).div(price)));
    }

    function getAmountQuoteForPriceDown(
        uint amountBase,
        uint reserveBase,
        uint reserveQuote,
        uint price,
        uint decimal)
    internal
    pure
    returns (uint amountQuote) {
        amountQuote = reserveQuote.sub((reserveBase.add(amountBase)).mul(price).div(10**decimal));
        //y' = y-(x+amountIn)*price
    }

    function getAmountBaseForPriceUp(
        uint amountQuote,
        uint reserveBase,
        uint reserveQuote,
        uint price,
        uint decimal)
    internal
    pure
    returns (uint amountBase) {
        amountBase = reserveBase.sub((reserveQuote.add(amountQuote)).mul(10**decimal).div(price));
        //x' = x-(y+amountOut)/price
    }

    //amountIn = (sqrt(9*x*x + 3988000*x*y/price)-1997*x)/1994 = (sqrt(x*(9*x + 3988000*y/price))-1997*x)/1994
    //amountOut = y-(x+amountIn)*price
    function getAmountForMovePrice(uint direction, uint reserveBase, uint reserveQuote, uint price, uint decimal)
    internal pure returns (uint amountBase, uint amountQuote, uint reserveBaseNew, uint reserveQuoteNew) {
        if (direction == LIMIT_BUY) {
            uint section1 = getSection1ForPriceUp(reserveBase, reserveQuote, price, decimal);
            uint section2 = reserveQuote.mul(1997);
            amountQuote = section1 > section2 ? (section1 - section2).div(1994) : 0;
            amountBase = amountQuote == 0 ? 0 : getAmountOut(amountQuote, reserveQuote, reserveBase);
            (reserveBaseNew, reserveQuoteNew) = (reserveBase - amountBase, reserveQuote + amountQuote);
        }
        else if (direction == LIMIT_SELL) {
            uint section1 = getSection1ForPriceDown(reserveBase, reserveQuote, price, decimal);
            uint section2 = reserveBase.mul(1997);
            amountBase = section1 > section2 ? (section1 - section2).div(1994) : 0;
            amountQuote = amountBase == 0 ? 0 : getAmountOut(amountBase, reserveBase, reserveQuote);
            (reserveBaseNew, reserveQuoteNew) = (reserveBase + amountBase, reserveQuote - amountQuote);
        }
        else {
            (reserveBaseNew, reserveQuoteNew) = (reserveBase, reserveQuote);
        }
    }

    //使用amountA数量的amountInOffer吃掉在价格price, 数量为amountOutOffer的tokenB, 返回实际消耗的tokenA数量和返回的tokenB的数量，amountOffer需要考虑手续费
    //手续费应该包含在amountOutWithFee中
    function getAmountOutForTakePrice(uint tradeDir, uint amountInOffer, uint price, uint decimal, uint orderAmount)
    internal pure returns (uint amountIn, uint amountOutWithFee, uint fee) {
        if (tradeDir == LIMIT_BUY) { //buy (quoteToken == tokenIn, swap quote token to base token)
            //amountOut = amountInOffer * price
            uint amountOut = getSellAmountWithPrice(amountInOffer, price, decimal);
            if (amountOut.mul(1000) <= orderAmount.mul(997)) { //amountOut <= orderAmount * (1-0.3%)
                amountIn = amountInOffer;
                fee = amountOut.mul(3).div(1000);
                amountOutWithFee = amountOut + fee;
            }
            else {
                amountOut = orderAmount.mul(997).div(1000);
                //amountIn = amountOutWithoutFee / price
                amountIn = getBuyAmountWithPrice(amountOut, price, decimal);
                amountOutWithFee = orderAmount;
                fee = amountOutWithFee.sub(amountOut);
            }
        }
        else if (tradeDir == LIMIT_SELL) { //sell (quoteToken == tokenOut, swap base token to quote token)
            //amountOut = amountInOffer / price --- 订单是买单
            uint amountOut = getBuyAmountWithPrice(amountInOffer, price, decimal);
            if (amountOut.mul(1000) <= orderAmount.mul(997)) { //amountOut <= orderAmount * (1-0.3%)
                amountIn = amountInOffer;
                fee = amountOut.mul(3).div(1000);
                amountOutWithFee = amountOut + fee;
            }
            else {
                amountOut = orderAmount.mul(997).div(1000);
                //amountIn = amountOutWithoutFee * price
                amountIn = getSellAmountWithPrice(amountOut, price, decimal);
                amountOutWithFee = orderAmount;
                fee = amountOutWithFee - amountOut;
            }
        }
    }

    //期望获得amountOutExpect，需要投入多少amountIn
    function getAmountInForTakePrice(uint tradeDir, uint amountOutExpect, uint price, uint decimal, uint orderAmount)
    internal pure returns (uint amountIn, uint amountOutWithFee, uint fee) {
        //buy (quoteToken == tokenIn)  用tokenIn（usdc)换tokenOut(btc) for take sell limit order
        if (tradeDir == LIMIT_BUY) {
            uint orderAmountWithoutFee = orderAmount.mul(997).div(1000);
            if (orderAmountWithoutFee <= amountOutExpect) { //吃掉所有
                amountOutWithFee = orderAmount;
                fee = amountOutWithFee - orderAmountWithoutFee;
                amountIn = getBuyAmountWithPrice(orderAmountWithoutFee, price, decimal);
            }
            else {
                amountOutWithFee = amountOutExpect;
                uint amountOutWithoutFee = amountOutExpect.mul(997).div(1000);
                fee = amountOutWithFee - amountOutWithoutFee;
                //amountIn = amountOutWithoutFee * price
                amountIn = getBuyAmountWithPrice(amountOutWithoutFee, price, decimal);
            }
        }
        //sell (quoteToken == tokenOut) 用tokenIn(btc)换tokenOut(usdc) for take buy limit order
        else if (tradeDir == LIMIT_SELL) {
            uint orderAmountWithoutFee = orderAmount.mul(997).div(1000);
            if (orderAmountWithoutFee <= amountOutExpect) { //吃掉所有
                amountOutWithFee = orderAmount;
                fee = amountOutWithFee - orderAmountWithoutFee;
                amountIn = getSellAmountWithPrice(orderAmountWithoutFee, price, decimal);
            }
            else {
                amountOutWithFee = amountOutExpect;
                uint amountOutWithoutFee = amountOutExpect.mul(997).div(1000);
                fee = amountOutWithFee - amountOutWithoutFee;
                amountIn = getSellAmountWithPrice(amountOutWithoutFee, price, decimal);
            }
        }
    }
}