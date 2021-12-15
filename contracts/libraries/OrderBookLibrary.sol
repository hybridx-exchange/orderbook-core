pragma solidity >=0.5.0;

import "../interfaces/IOrderBook.sol";
import "../interfaces/IOrderBookFactory.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IWETH.sol";
import '../libraries/TransferHelper.sol';
import "./Math.sol";
import "./SafeMath.sol";

library OrderBookLibrary {
    using SafeMath for uint;
    using SafeMath for uint112;

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

    //get buy amount with price based on price and offered funds
    function getBuyAmountWithPrice(uint amountOffer, uint price, uint decimal) internal pure returns (uint amountGet){
        amountGet = amountOffer.mul(10 ** decimal).div(price);
    }

    //get buy amount with price based on price and offered funds
    function getSellAmountWithPrice(uint amountOffer, uint price, uint decimal) internal pure returns (uint amountGet){
        amountGet = amountOffer.mul(price).div(10 ** decimal);
    }

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

    // fetches and sorts the reserves for a pair
    function getReserves(address pair, address tokenA, address tokenB) internal view returns
    (uint112 reserveA, uint112 reserveB) {
        require(tokenA != tokenB, 'OrderBookLibrary: IDENTICAL_ADDRESSES');
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        require(token0 != address(0), 'OrderBookLibrary: ZERO_ADDRESS');
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getPrice(address pair, address baseToken, address quoteToken, uint decimal)
    internal
    view
    returns (uint price) {
        (uint112 reserveBase, uint112 reserveQuote) = getReserves(pair, baseToken, quoteToken);
        if (reserveBase != 0) {
            uint d = reserveQuote.mul(10 ** decimal);
            price = d.div(reserveBase);
        }
    }

    //sqrt(9*x*x + 3988000*x*y*price)
    function getSection1ForBuyLimit(uint reserveIn, uint reserveOut, uint price, uint decimal)
    internal
    pure
    returns (uint section1) {
        section1 = Math.sqrt(reserveIn.mul(reserveIn).mul(9).add(reserveIn.mul(reserveOut).mul(3988000).mul
        (price).div(10**decimal)));
    }

    //sqrt(9*x*x + 3988000*x*y/price)
    function getSection1ForSellLimit(uint reserveIn, uint reserveOut, uint price, uint decimal)
    internal
    pure
    returns (uint section1) {
        section1 = Math.sqrt(reserveIn.mul(reserveIn).mul(9).add(reserveIn.mul(reserveOut).mul(3988000).mul
        (10**decimal).div(price)));
    }

    function getAmountOutForAmmMovePrice(
        uint direction,
        uint amountIn,
        uint reserveIn,
        uint reserveOut,
        uint price,
        uint decimal)
    internal
    pure
    returns (uint amountOut) {
        amountOut = direction == LIMIT_BUY ? reserveOut.sub((reserveIn.add(amountIn)).div(price).div(10**decimal)) : //y-(x+amountIn)/price
            reserveOut.sub((reserveIn.add(amountIn)).mul(price).div(10**decimal)); //y-(x+amountIn)*price
    }

    function ammMovePrice(
        uint direction,
        uint reserveIn,
        uint reserveOut,
        uint price,
        uint decimal,
        uint _amountLeft,
        uint _amountAmmIn,
        uint _amountAmmOut)
    internal
    pure
    returns (uint amountLeft, uint amountAmmIn, uint amountAmmOut) {
        uint amountInUsed;
        uint amountOutUsed;
        (amountInUsed, amountOutUsed, reserveIn, reserveOut) =
        getAmountForAmmMovePrice(
            direction,
            reserveIn,
            reserveOut,
            price,
            decimal);
        if (amountInUsed > _amountLeft) {
            amountAmmIn = _amountAmmIn + _amountLeft;
            amountAmmOut = _amountAmmOut + getAmountOut(_amountLeft, reserveIn, reserveOut);
            amountLeft = 0;
        }
        else {
            amountAmmIn = _amountAmmIn + amountInUsed;
            amountAmmOut = _amountAmmOut + amountOutUsed;
            amountLeft = _amountLeft - amountInUsed;
        }
    }

    //将价格移动到price需要消息的tokenA的数量, 以及新的reserveIn, reserveOut
    //amountIn = (sqrt(9*x*x + 3988000*x*y/price)-1997*x)/1994 = (sqrt(x*(9*x + 3988000*y/price))-1997*x)/1994
    //amountOut = y-(x+amountIn)*price
    function getAmountForAmmMovePrice(uint direction, uint reserveIn, uint reserveOut, uint price, uint decimal)
    internal pure returns (uint amountIn, uint amountOut, uint reserveInNew, uint reserveOutNew) {
        if (direction == LIMIT_BUY) {
            uint section1 = getSection1ForBuyLimit(reserveIn, reserveOut, price, decimal);
            uint section2 = reserveIn.mul(1997);
            amountIn = section1 > section2 ? (section1 - section2).div(1994) : 0;
            amountOut = amountIn == 0 ? 0 :
                getAmountOutForAmmMovePrice(direction, amountIn, reserveIn, reserveOut, price, decimal);
            (reserveInNew, reserveOutNew) = (reserveIn + amountIn, reserveOut - amountOut);
        }
        else if (direction == LIMIT_SELL) {
            uint section1 = getSection1ForSellLimit(reserveIn, reserveOut, price, decimal);
            uint section2 = reserveIn.mul(1997);
            amountIn = section1 > section2 ? (section1 - section2).div(1994) : 0;
            amountOut = amountIn == 0 ? 0 :
                getAmountOutForAmmMovePrice(direction, amountIn, reserveIn, reserveOut, price, decimal);
            (reserveInNew, reserveOutNew) = (reserveIn + amountIn, reserveOut - amountOut);
        }
        else {
            (reserveInNew, reserveOutNew) = (reserveIn, reserveOut);
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

    function safeTransfer(address token, address to, uint value)
    internal {
        TransferHelper.safeTransfer(token, to, value);
    }

    function batchTransfer(address factory, address token, address[] memory accounts, uint[] memory amounts) internal {
        address WETH = IOrderBookFactory(factory).WETH();
        for(uint i=0; i<accounts.length; i++) {
            if (WETH == token){
                IWETH(WETH).withdraw(amounts[i]);
                TransferHelper.safeTransferETH(accounts[i], amounts[i]);
            }
            else {
                safeTransfer(token, accounts[i], amounts[i]);
            }
        }
    }

    function singleTransfer(address factory, address token, address to, uint amount) internal {
        address WETH = IOrderBookFactory(factory).WETH();
        if (token == WETH) {
            IWETH(WETH).withdraw(amount);
            TransferHelper.safeTransferETH(to, amount);
        }
        else{
            safeTransfer(token, to, amount);
        }
    }
}