pragma solidity >=0.5.0;

import "../interfaces/IOrderBook.sol";
import "../interfaces/IOrderBookFactory.sol";
import "../interfaces/IUniswapV2Factory.sol";
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

    function getAdmin(address factory) internal view returns (address admin){
        admin = IUniswapV2Factory(IOrderBookFactory(factory).pairFactory()).admin();
    }

    function getUniswapV2OrderBookFactory(address factory) internal view returns (address factoryRet){
        factoryRet = IUniswapV2Factory(IOrderBookFactory(factory).pairFactory()).getOrderBookFactory();
    }

    //get quote amount with base amount at price --- y = x * p / x_decimal
    function getQuoteAmountWithBaseAmountAtPrice(uint amountBase, uint price, uint baseDecimal)
    internal
    pure
    returns (uint amountGet) {
        amountGet = amountBase.mul(price).div(10 ** baseDecimal);
    }

    //get base amount with quote amount at price --- x = y * x_decimal / p
    function getBaseAmountWithQuoteAmountAtPrice(uint amountQuote, uint price, uint baseDecimal)
    internal
    pure
    returns (uint amountGet) {
        amountGet = amountQuote.mul(10 ** baseDecimal).div(price);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address pair, address tokenA, address tokenB) internal view returns
    (uint112 reserveA, uint112 reserveB) {
        require(tokenA != tokenB, 'IDENTICAL_ADDRESSES');
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        require(token0 != address(0), 'ZERO_ADDRESS');
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // get lp price
    function getPrice(uint reserveBase, uint reserveQuote, uint baseDecimal) internal pure returns (uint price){
        if (reserveBase != 0) {
            price = reserveQuote.mul(10 ** baseDecimal) / reserveBase;
        }
    }

    // Make up for the LP price error caused by the loss of precision,
    // increase the LP price a bit, and ensure that the buy order price is less than or equal to the LP price
    function getFixAmountForMovePriceUp(uint _amountLeft, uint _amountAmmQuote,
        uint reserveBase, uint reserveQuote, uint targetPrice, uint baseDecimal)
    internal pure returns (uint amountLeft, uint amountAmmQuote, uint amountQuoteFix) {
        uint curPrice = getPrice(reserveBase, reserveQuote, baseDecimal);
        // y' = x.p2 - x.p1, x does not change, increase y, make the price bigger
        if (curPrice < targetPrice) {
            amountQuoteFix = (reserveBase.mul(targetPrice).div(10 ** baseDecimal)
                .sub(reserveBase.mul(curPrice).div(10 ** baseDecimal)));
            amountQuoteFix = amountQuoteFix > 0 ? amountQuoteFix : 1;
            require(_amountLeft >= amountQuoteFix, "Not Enough Output Amount");
            (amountLeft, amountAmmQuote) = (_amountLeft.sub(amountQuoteFix), _amountAmmQuote + amountQuoteFix);
        }
        else {
            (amountLeft, amountAmmQuote) = (_amountLeft, _amountAmmQuote);
        }
    }

    // Make up for the LP price error caused by the loss of precision,
    // reduce the LP price a bit, and ensure that the order price is greater than or equal to the LP price
    function getFixAmountForMovePriceDown(uint _amountLeft, uint _amountAmmBase,
        uint reserveBase, uint reserveQuote, uint targetPrice, uint baseDecimal)
    internal pure returns (uint amountLeft, uint amountAmmBase, uint amountBaseFix) {
        uint curPrice = getPrice(reserveBase, reserveQuote, baseDecimal);
        //x' = y/p1 - y/p2, y is unchanged, increasing x makes the price smaller
        if (curPrice > targetPrice) {
            amountBaseFix = (reserveQuote.mul(10 ** baseDecimal).div(targetPrice)
            .sub(reserveQuote.mul(10 ** baseDecimal).div(curPrice)));
            amountBaseFix = amountBaseFix > 0 ? amountBaseFix : 1;
            require(_amountLeft >= amountBaseFix, "Not Enough Input Amount");
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

    //amountIn = (sqrt(9*x*x + 3988000*x*y/price)-1997*x)/1994 = (sqrt(x*(9*x + 3988000*y/price))-1997*x)/1994
    //amountOut = y-(x+amountIn)*price
    function getAmountForMovePrice(
        uint direction,
        uint amountIn,
        uint reserveBase,
        uint reserveQuote,
        uint price,
        uint decimal)
    internal
    pure
    returns (uint amountInLeft, uint amountBase, uint amountQuote, uint reserveBaseNew, uint reserveQuoteNew) {
        if (direction == LIMIT_BUY) {
            uint section1 = getSection1ForPriceUp(reserveBase, reserveQuote, price, decimal);
            uint section2 = reserveQuote.mul(1997);
            amountQuote = section1 > section2 ? (section1 - section2).div(1994) : 0;
            amountQuote = amountQuote > amountIn ? amountIn : amountQuote;
            amountBase = amountQuote == 0 ? 0 : getAmountOut(amountQuote, reserveQuote, reserveBase);//此处重复计算了0.3%的手续费?
            (amountInLeft, reserveBaseNew, reserveQuoteNew) =
                (amountIn - amountQuote, reserveBase - amountBase, reserveQuote + amountQuote);
        }
        else if (direction == LIMIT_SELL) {
            uint section1 = getSection1ForPriceDown(reserveBase, reserveQuote, price, decimal);
            uint section2 = reserveBase.mul(1997);
            amountBase = section1 > section2 ? (section1 - section2).div(1994) : 0;
            amountBase = amountBase > amountIn ? amountIn : amountBase;
            amountQuote = amountBase == 0 ? 0 : getAmountOut(amountBase, reserveBase, reserveQuote);
            (amountInLeft, reserveBaseNew, reserveQuoteNew) =
                (amountIn - amountBase, reserveBase + amountBase, reserveQuote - amountQuote);
        }
        else {
            (amountInLeft, reserveBaseNew, reserveQuoteNew) = (amountIn, reserveBase, reserveQuote);
        }
    }

    //amountIn = (sqrt(9*x*x + 3988000*x*y/price)-1997*x)/1994 = (sqrt(x*(9*x + 3988000*y/price))-1997*x)/1994
    //amountOut = y-(x+amountIn)*price
    function getAmountForMovePriceWithAmountOut(
        uint direction,
        uint amountOut,
        uint reserveBase,
        uint reserveQuote,
        uint price,
        uint decimal)
    internal
    pure
    returns (uint amountOutLeft, uint amountBase, uint amountQuote, uint reserveBaseNew, uint reserveQuoteNew) {
        if (direction == LIMIT_BUY) {
            uint section1 = getSection1ForPriceUp(reserveBase, reserveQuote, price, decimal);
            uint section2 = reserveQuote.mul(1997);
            amountQuote = section1 > section2 ? (section1 - section2).div(1994) : 0;
            amountBase = amountQuote == 0 ? 0 : getAmountOut(amountQuote, reserveQuote, reserveBase);
            if (amountBase > amountOut) {
                amountBase = amountOut;
                amountQuote = getAmountIn(amountBase, reserveQuote, reserveBase);
            }
            (amountOutLeft, reserveBaseNew, reserveQuoteNew) =
                (amountOut - amountBase, reserveBase - amountBase, reserveQuote + amountQuote);
        }
        else if (direction == LIMIT_SELL) {
            uint section1 = getSection1ForPriceDown(reserveBase, reserveQuote, price, decimal);
            uint section2 = reserveBase.mul(1997);
            amountBase = section1 > section2 ? (section1 - section2).div(1994) : 0;
            amountQuote = amountBase == 0 ? 0 : getAmountOut(amountBase, reserveBase, reserveQuote);
            if (amountQuote > amountOut) {
                amountQuote = amountOut;
                amountBase = getAmountIn(amountQuote, reserveBase, reserveQuote);
            }
            (amountOutLeft, reserveBaseNew, reserveQuoteNew) =
            (amountOut - amountQuote, reserveBase + amountBase, reserveQuote - amountQuote);
        }
        else {
            (amountOutLeft, reserveBaseNew, reserveQuoteNew) = (amountOut, reserveBase, reserveQuote);
        }
    }

    // get the output after taking the order using amountInOffer
    // The protocol fee should be included in the amountOutWithFee
    function getAmountOutForTakePrice(
        uint tradeDir,
        uint amountInOffer,
        uint price,
        uint decimal,
        uint protocolFeeRate,
        uint subsidyFeeRate,
        uint orderAmount)
    internal pure returns (uint amountInUsed, uint amountOutWithFee, uint communityFee) {
        uint fee;
        if (tradeDir == LIMIT_BUY) { //buy (quoteToken == tokenIn, swap quote token to base token)
            //amountOut = amountInOffer / price
            uint amountOut = getBaseAmountWithQuoteAmountAtPrice(amountInOffer, price, decimal);
            if (amountOut.mul(10000) <= orderAmount.mul(10000-protocolFeeRate)) { //amountOut <= orderAmount * (1-0.3%)
                amountInUsed = amountInOffer;
                fee = amountOut.mul(protocolFeeRate).div(10000);
                amountOutWithFee = amountOut + fee;
            }
            else {
                amountOut = orderAmount.mul(10000-protocolFeeRate).div(10000);
                //amountIn = amountOutWithoutFee * price
                amountInUsed = getQuoteAmountWithBaseAmountAtPrice(amountOut, price, decimal);
                amountOutWithFee = orderAmount;
                fee = amountOutWithFee.sub(amountOut);
            }
        }
        else if (tradeDir == LIMIT_SELL) { //sell (quoteToken == tokenOut, swap base token to quote token)
            //amountOut = amountInOffer * price ========= match limit buy order
            uint amountOut = getQuoteAmountWithBaseAmountAtPrice(amountInOffer, price, decimal);
            if (amountOut.mul(10000) <= orderAmount.mul(10000-protocolFeeRate)) { //amountOut <= orderAmount * (1-0.3%)
                amountInUsed = amountInOffer;
                fee = amountOut.mul(protocolFeeRate).div(10000);
                amountOutWithFee = amountOut + fee;
            }
            else {
                amountOut = orderAmount.mul(10000-protocolFeeRate).div(10000);
                //amountIn = amountOutWithoutFee / price
                amountInUsed = getBaseAmountWithQuoteAmountAtPrice(amountOut, price, decimal);
                amountOutWithFee = orderAmount;
                fee = amountOutWithFee - amountOut;
            }
        }

        // (fee * 100 - fee * subsidyFeeRate) / 100
        communityFee = (fee.mul(100).sub(fee.mul(subsidyFeeRate))).div(100);
    }

    //get the input after taking the order with amount out
    function getAmountInForTakePrice(
        uint tradeDir,
        uint amountOutExpect,
        uint price,
        uint decimal,
        uint protocolFeeRate,
        uint subsidyFeeRate,
        uint orderAmount)
    internal pure returns (uint amountIn, uint amountOutWithFee, uint communityFee) {
        uint orderProtocolFeeAmount = orderAmount.mul(protocolFeeRate).div(10000);
        uint orderSubsidyFeeAmount = orderProtocolFeeAmount.mul(subsidyFeeRate).div(100);
        uint orderAmountWithSubsidyFee = orderAmount.sub(orderProtocolFeeAmount.sub(orderSubsidyFeeAmount));
        uint amountOutWithoutFee;
        if (orderAmountWithSubsidyFee <= amountOutExpect) { //take all amount of order
            amountOutWithFee = orderAmount;
            communityFee = amountOutWithFee.sub(orderAmountWithSubsidyFee);
            amountOutWithoutFee = orderAmountWithSubsidyFee.sub(orderSubsidyFeeAmount);
        }
        else {
            orderAmountWithSubsidyFee = amountOutExpect;
            //amountOutWithFee * (1 - (protocolFeeRate / 10000 * subsidyFeeRate / 100) = orderAmountWithSubsidyFee
            //=> amountOutWithFee = orderAmountWithSubsidyFee * 1000000 / (1000000 - protocolFeeRate *
            //subsidyFeeRate)
            amountOutWithFee = orderAmountWithSubsidyFee.mul(1000000).div(1000000 - protocolFeeRate * subsidyFeeRate);
            //amountOutWithoutFee = amountOutWithFee * (10000-protocolFeeRate) / 10000
            //amountOutWithoutFee = (orderAmountWithSubsidyFee * 1000000 / (1000000 - protocolFeeRate *
            //subsidyFeeRate)) * ((10000 - protocolFeeRate) / 10000)
            //((orderAmountWithSubsidyFee * 1000000) * (10000 - protocolFeeRate)) / ((1000000 - protocolFeeRate *
            //subsidyFeeRate) * 10000)
            amountOutWithoutFee = orderAmountWithSubsidyFee.mul(100).mul(10000 - protocolFeeRate).
                div(1000000 - protocolFeeRate * subsidyFeeRate);
            communityFee = amountOutWithFee.sub(orderAmountWithSubsidyFee);
        }

        if (tradeDir == LIMIT_BUY) {
            amountIn = getQuoteAmountWithBaseAmountAtPrice(amountOutWithoutFee, price, decimal);
        }
        else if (tradeDir == LIMIT_SELL) {
            amountIn = getBaseAmountWithQuoteAmountAtPrice(amountOutWithoutFee, price, decimal);
        }
    }
}