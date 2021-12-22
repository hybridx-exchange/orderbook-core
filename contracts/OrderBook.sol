pragma solidity =0.5.16;

//pragma experimental ABIEncoderV2;//for decode [] output

import "./libraries/OrderBookLibrary.sol";
import "./libraries/Arrays.sol";
import "./OrderBookBase.sol";

contract OrderBook is OrderBookBase {
    using SafeMath for uint;
    using SafeMath for uint112;
    using Arrays for address[];
    using Arrays for uint[];

    function _getAmountAndTakePrice(
        uint direction,
        uint amountInOffer,
        uint price,
        uint decimal,
        uint orderAmount)
    internal
    returns (uint amountIn, uint amountOutWithFee, uint fee, address[] memory accountsTo, uint[] memory amountsTo) {
        if (direction == LIMIT_BUY) { //buy (quoteToken == tokenIn, swap quote token to base token)
            //amountOut = amountInOffer / price
            uint amountOut = OrderBookLibrary.getBuyAmountWithPrice(amountInOffer, price, decimal);
            if (amountOut.mul(1000) <= orderAmount.mul(997)) { //amountOut <= orderAmount * (1-0.3%)
                amountIn = amountInOffer;
                fee = amountOut.mul(3).div(1000);
                amountOutWithFee = amountOut + fee;
            }
            else {
                amountOut = orderAmount.mul(997).div(1000);
                //amountIn = amountOutWithoutFee * price
                amountIn = OrderBookLibrary.getSellAmountWithPrice(amountOut, price, decimal);
                amountOutWithFee = orderAmount;
                fee = amountOutWithFee.sub(amountOut);
            }
            (accountsTo, amountsTo, ) = _takeLimitOrder(LIMIT_SELL, amountOutWithFee, price);
        }
        else if (direction == LIMIT_SELL) { //sell (quoteToken == tokenOut, swap base token to quote token)
            //amountOut = amountInOffer * price
            uint amountOut = OrderBookLibrary.getSellAmountWithPrice(amountInOffer, price, decimal);
            if (amountOut.mul(1000) <= orderAmount.mul(997)) { //amountOut <= orderAmount * (1-0.3%)
                amountIn = amountInOffer;
                fee = amountOut.mul(3).div(1000);
                amountOutWithFee = amountOut + fee;
            }
            else {
                amountOut = orderAmount.mul(997).div(1000);
                //amountIn = amountOutWithoutFee / price
                amountIn = OrderBookLibrary.getBuyAmountWithPrice(amountOut, price, decimal);
                amountOutWithFee = orderAmount;
                fee = amountOutWithFee - amountOut;
            }
            (accountsTo, amountsTo, ) = _takeLimitOrder(LIMIT_BUY, amountOutWithFee, price);
        }
    }

    function getAmountAndTakePrice(
        address to,
        uint direction,//TRADE DIRECTION
        uint amountInOffer,
        uint price,
        uint decimal,
        uint orderAmount)
    internal
    returns (uint amountIn, uint amountOutWithFee, address[] memory accounts, uint[] memory amounts) {
        (amountIn, amountOutWithFee, , accounts, amounts) =
            _getAmountAndTakePrice(direction, amountInOffer, price, decimal, orderAmount);

        //当token为weth时，外部调用的时候直接将weth转出
        address tokenOut = direction == LIMIT_BUY ? baseToken : quoteToken;
        _safeTransfer(tokenOut, to, amountOutWithFee);
    }

    function _orderBookMovePrice(
        uint direction,
        uint _reserveBase,
        uint _reserveQuote,
        uint price,
        uint _amountLeft,
        uint _amountAmmBase,
        uint _amountAmmQuote)
    internal
    view
    returns (uint amountLeft, uint reserveBase, uint reserveQuote, uint amountAmmBase, uint amountAmmQuote) {
        uint amountBaseUsed;
        uint amountQuoteUsed;
        (amountBaseUsed, amountQuoteUsed, reserveBase, reserveQuote) =
        OrderBookLibrary.getAmountForMovePrice(
            direction,
            _reserveBase,
            _reserveQuote,
            price,
            priceDecimal);
        if (direction == LIMIT_BUY) {
            if (amountQuoteUsed > _amountLeft) {
                amountAmmQuote = _amountAmmQuote + _amountLeft;
                amountAmmBase = _amountAmmBase +
                    OrderBookLibrary.getAmountOut(_amountLeft, _reserveQuote, _reserveBase);
                amountLeft = 0;
            }
            else {
                amountAmmQuote = _amountAmmQuote +  amountQuoteUsed;
                amountAmmBase = _amountAmmBase + amountBaseUsed;
                amountLeft = _amountLeft - amountQuoteUsed;
            }
        }
        else {
            if (amountBaseUsed > _amountLeft) {
                amountAmmBase = _amountAmmBase + _amountLeft;
                amountAmmQuote = _amountAmmQuote +
                    OrderBookLibrary.getAmountOut(_amountLeft, _reserveBase, _reserveQuote);
                amountLeft = 0;
            }
            else {
                amountAmmBase = _amountAmmBase + amountBaseUsed;
                amountAmmQuote = _amountAmmQuote + amountQuoteUsed;
                amountLeft = _amountLeft - amountBaseUsed;
            }
        }
    }

    function _ammSwapPrice(
        address to,
        address tokenIn,
        address tokenOut,
        uint amountAmmIn,
        uint amountAmmOut) internal {

        _safeTransfer(tokenIn, pair, amountAmmIn);

        (uint amount0Out, uint amount1Out) = tokenOut == IUniswapV2Pair(pair).token1() ?
            (uint(0), amountAmmOut) : (amountAmmOut, uint(0));

        address WETH = IOrderBookFactory(factory).WETH();
        if (WETH == tokenOut) {
            IUniswapV2Pair(pair).swapOriginal(amount0Out, amount1Out, address(this), new bytes(0));
            IWETH(WETH).withdraw(amountAmmOut);
            TransferHelper.safeTransferETH(to, amountAmmOut);
        }
        else {
            IUniswapV2Pair(pair).swapOriginal(amount0Out, amount1Out, to, new bytes(0));
        }

        IUniswapV2Pair(pair).sync();
    }

    /*
        swap to price1 and take the order with price of price1 and
        swap to price2 and take the order with price of price2
        ......
        until all offered amount of limit order is consumed or price == target.
    */
    function _movePriceUp(
        uint amountOffer,
        uint targetPrice,
        address to)
    private
    returns (uint amountLeft) {
        (uint reserveBase, uint reserveQuote) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);
        uint amountAmmBase;
        uint amountAmmQuote;
        uint amountOrderBookOut;
        amountLeft = amountOffer;

        uint price = nextPrice(LIMIT_SELL, 0);
        uint amount = price != 0 ? listAgg(LIMIT_SELL, price) : 0;
        while (price != 0 && price <= targetPrice) {
            //skip if there is no liquidity in lp pool
            if (reserveBase > 0 && reserveQuote > 0 && price < targetPrice) {
                (amountLeft, reserveBase, reserveQuote, amountAmmBase, amountAmmQuote) =
                    _orderBookMovePrice(LIMIT_BUY, reserveBase, reserveQuote, price,
                        amountLeft, amountAmmBase, amountAmmQuote);
                if (amountLeft == 0) {
                    break;
                }
            }

            //take the order of price 'price'.
            (uint amountInForTake,
            uint amountOutWithFee,,
            address[] memory accounts,
            uint[] memory amounts) =
                _getAmountAndTakePrice(LIMIT_BUY, amountLeft, price, priceDecimal, amount);
            amountOrderBookOut += amountOutWithFee;
            _batchTransfer(quoteToken, accounts, amounts);

            amountLeft = amountInForTake < amountLeft ? amountLeft - amountInForTake : 0;
            if (amountLeft == 0) {  //break if there is no amount left.
                break;
            }

            price = nextPrice(LIMIT_SELL, price);
            amount = price != 0 ? listAgg(LIMIT_SELL, price) : 0;
        }

        // send the user for take all limit order's amount.
        if (amountOrderBookOut > 0) {
            _singleTransfer(baseToken, to, amountOrderBookOut);
        }

        // swap to target price when there is no limit order less than the target price
        if (price < targetPrice && amountLeft > 0) {
            (amountLeft, reserveBase, reserveQuote, amountAmmBase, amountAmmQuote) =
            _orderBookMovePrice(LIMIT_BUY, reserveBase, reserveQuote, targetPrice,
                amountLeft, amountAmmBase, amountAmmQuote);
        }

        if (amountAmmQuote > 0) {
            if (amountLeft > 0) {
                (amountLeft, amountAmmQuote,) =
                    OrderBookLibrary.getFixAmountForMovePriceUp(amountLeft, amountAmmQuote, reserveBase, reserveQuote,
                        targetPrice, priceDecimal);
            }

            _ammSwapPrice(to, quoteToken, baseToken, amountAmmQuote, amountAmmBase);
            require(amountLeft == 0 || getPrice() >= targetPrice, "Hybridx OrderBook: Buy price mismatch");

            quoteBalance = _getQuoteBalance();
        }
    }

    /*
        swap to price1 and take the order with price of price1 and
        swap to price2 and take the order with price of price2
        ......
        until all offered amount of limit order is consumed or price == target.
    */
    function _movePriceDown(
        uint amountOffer,
        uint targetPrice,
        address to)
    private
    returns (uint amountLeft) {
        (uint reserveBase, uint reserveQuote) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);
        amountLeft = amountOffer;
        uint amountAmmBase;
        uint amountAmmQuote;
        uint amountOrderBookOut;

        uint price = nextPrice(LIMIT_BUY, 0);
        uint amount = price != 0 ? listAgg(LIMIT_BUY, price) : 0;
        while (price != 0 && price >= targetPrice) {
            //skip if there is no liquidity in lp pool
            if (reserveBase > 0 && reserveQuote > 0 && price > targetPrice) {
                (amountLeft, reserveBase, reserveQuote, amountAmmBase, amountAmmQuote) =
                    _orderBookMovePrice(LIMIT_SELL, reserveBase, reserveQuote, price,
                        amountLeft, amountAmmBase, amountAmmQuote);
                if (amountLeft == 0) {
                    break;
                }
            }

            //take the order of price 'price'.
            (uint amountInForTake,
            uint amountOutWithFee,,
            address[] memory accounts,
            uint[] memory amounts) = _getAmountAndTakePrice(LIMIT_SELL, amountLeft, price, priceDecimal, amount);
            amountOrderBookOut += amountOutWithFee;
            _batchTransfer(baseToken, accounts, amounts);

            amountLeft = amountInForTake < amountLeft ? amountLeft - amountInForTake : 0;
            if (amountLeft == 0) { //break if there is no amount left.
                break;
            }

            price = nextPrice(LIMIT_BUY, price);
            amount = price != 0 ? listAgg(LIMIT_BUY, price) : 0;
        }

        // send the user for take all limit order's amount.
        if (amountOrderBookOut > 0) {
            _singleTransfer(quoteToken, to, amountOrderBookOut);
        }

        // swap to target price when there is no limit order less than the target price
        if (price == 0 || price > targetPrice && amountLeft > 0) {
            (amountLeft, reserveBase, reserveQuote, amountAmmBase, amountAmmQuote) =
                _orderBookMovePrice(LIMIT_SELL, reserveBase, reserveQuote, targetPrice,
                    amountLeft, amountAmmBase, amountAmmQuote);
        }

        if (amountAmmBase > 0) {
            if (amountLeft > 0) {
                (amountLeft, amountAmmBase,) =
                    OrderBookLibrary.getFixAmountForMovePriceDown(amountLeft, amountAmmBase, reserveBase, reserveQuote,
                        targetPrice, priceDecimal);
            }

            _ammSwapPrice(to, baseToken, quoteToken, amountAmmBase, amountAmmQuote);

            //update base balance
            baseBalance = _getBaseBalance();

            require(amountLeft == 0 || getPrice() <= targetPrice, "Hybridx OrderBook: sell to target failed");
        }
    }

    //limit order for buy base token with quote token
    //对于市价单，如果订单数量不是最小订单的整数倍，考虑一下是否需要退回
    function createBuyLimitOrder(
        address user,
        uint price,
        address to)
    external
    lock
    returns (uint orderId) {
        require(price > 0 && price % priceStep == 0, 'Hybridx OrderBook: Price Invalid');

        //get input amount of quote token for buy limit order
        uint balance = _getQuoteBalance();
        uint amountOffer = balance > quoteBalance ? balance - quoteBalance : 0;
        require(amountOffer >= minAmount, 'Hybridx OrderBook: Amount Invalid');

        IUniswapV2Pair(pair).sync();
        uint amountRemain = _movePriceUp(amountOffer, price, to);
        if (amountRemain != 0) {
            orderId = _addLimitOrder(user, to, amountOffer, amountRemain, price, LIMIT_BUY);
            emit OrderCreated(user, to, amountOffer, amountRemain, price, LIMIT_BUY);
        }

        //update quote balance
        quoteBalance = amountRemain != amountOffer ? _getQuoteBalance() : balance;
    }

    //limit order for sell base token to quote token
    function createSellLimitOrder(
        address user,
        uint price,
        address to)
    external
    lock
    returns (uint orderId) {
        require(price > 0 && (price % priceStep) == 0, 'Hybridx OrderBook: Price Invalid');

        //get input amount of base token for sell limit order
        uint balance = _getBaseBalance();
        uint amountOffer = balance > baseBalance ? balance - baseBalance : 0;
        require(amountOffer >= minAmount, 'Hybridx OrderBook: Amount Invalid');

        IUniswapV2Pair(pair).sync();
        uint amountRemain = _movePriceDown(amountOffer, price, to);
        if (amountRemain != 0) {
            orderId = _addLimitOrder(user, to, amountOffer, amountRemain, price, LIMIT_SELL);
            emit OrderCreated(user, to, amountOffer, amountRemain, price, LIMIT_SELL);
        }

        //update base balance
        baseBalance = amountRemain != amountOffer ? _getBaseBalance() : balance;
    }

    function cancelLimitOrder(uint orderId) external lock {
        Order memory o = marketOrders[orderId];
        require(o.owner == msg.sender);

        _removeLimitOrder(o);

        //refund
        address token = o.orderType == LIMIT_BUY ? quoteToken : baseToken;
        _singleTransfer(token, o.to, o.amountRemain);

        //update token balance
        uint balance = IERC20(token).balanceOf(address(this));
        if (o.orderType == LIMIT_BUY) quoteBalance = balance;
        else baseBalance = balance;

        emit OrderCanceled(o.owner, o.to, o.amountOffer, o.amountRemain, o.price, o.orderType);
    }

    function _takeLimitOrder(
        uint direction,
        uint amount,
        uint price)
    internal
    returns (address[] memory accountsTo, uint[] memory amountsTo, uint amountUsed) {
        uint amountLeft = amount;
        uint index;
        uint length = length(direction, price);
        accountsTo = new address[](length);
        amountsTo = new uint[](length);
        uint decimal = priceDecimal;
        while (index < length && amountLeft > 0) {
            uint orderId = peek(direction, price);
            Order memory order = marketOrders[orderId];
            require(orderId == order.orderId && order.orderType == direction && price == order.price,
                'Hybridx OrderBook: Order Invalid');
            accountsTo[index] = order.to;
            uint amountTake = amountLeft > order.amountRemain ? order.amountRemain : amountLeft;
            order.amountRemain = order.amountRemain - amountTake;
            amountsTo[index] = direction == LIMIT_BUY ?
                OrderBookLibrary.getBuyAmountWithPrice(amountTake.mul(997).div(1000), price, decimal) :
                OrderBookLibrary.getSellAmountWithPrice(amountTake.mul(997).div(1000), price, decimal);

            if (order.amountRemain != 0) {
                marketOrders[orderId].amountRemain = order.amountRemain;
                emit OrderUpdate(order.owner, order.to, order.price, order.amountOffer, order
                    .amountRemain, order.orderType);
                break;
            }

            pop(direction, price);
            emit OrderClosed(order.owner, order.to, order.price, order.amountOffer, order
                .amountRemain, order.orderType);

            delete marketOrders[orderId];

            //delete user order
            uint userOrderSize = userOrders[order.owner].length;
            require(userOrderSize > order.orderIndex);
            //overwrite the current element with the last element directly
            userOrders[order.owner][order.orderIndex] = userOrders[order.owner][userOrderSize - 1];
            //delete the last element
            userOrders[order.owner].pop();

            amountLeft = amountLeft - amountTake;
        }

        amountUsed = amount - amountLeft;
    }

    //take buy limit order
    function takeBuyLimitOrder(
        uint amount,
        uint price)
    public
    lock
    returns (address[] memory accounts, uint[] memory amounts, uint amountUsed) {
        (accounts, amounts, amountUsed) = _takeLimitOrder(LIMIT_BUY, amount, price);
        //向pair合约转账amountUsed的baseToken
        _safeTransfer(baseToken, pair, amountUsed);
        //update base balance
        baseBalance = _getBaseBalance();
    }

    //take sell limit order
    function takeSellLimitOrder(
        uint amount,
        uint price)
    public
    lock
    returns (address[] memory accounts, uint[] memory amounts, uint amountUsed){
        (accounts, amounts, amountUsed) = _takeLimitOrder(LIMIT_SELL, amount, price);
        //向pair合约转账amountUsed
        _safeTransfer(quoteToken, pair, amountUsed);
        //update quote balance
        quoteBalance = _getQuoteBalance();
    }

    //更新价格间隔
    function priceStepUpdate(uint newPriceStep) external lock {
        require(priceLength(LIMIT_BUY) == 0 && priceLength(LIMIT_SELL) == 0,
            'Hybridx OrderBook: Order Exist');
        priceStep = newPriceStep;
    }

    //更新最小数量
    function minAmountUpdate(uint newMinAmount) external lock {
        require(priceLength(LIMIT_BUY) == 0 && priceLength(LIMIT_SELL) == 0,
            'Hybridx OrderBook: Order Exist');
        minAmount = newMinAmount;
    }

    /*******************************************************************************************************
                                    called by uniswap v2 pair and router
     *******************************************************************************************************/
    function getAmountOutForMovePrice(address tokenIn, uint amountInOffer, uint reserveIn, uint reserveOut)
    external
    view
    returns (uint amountOutGet, uint amountInLeft, uint reserveInRet, uint reserveOutRet){
        (reserveInRet, reserveOutRet) = (reserveIn, reserveOut);
        uint tradeDir = tradeDirection(tokenIn);
        uint orderDir = OrderBookLibrary.getOppositeDirection(tradeDir); // 订单方向与交易方向相反
        amountInLeft = amountInOffer;
        amountOutGet = 0;
        (uint price, uint amount) = nextBook(orderDir, 0);
        while (price != 0) {
            uint amountInUsed;
            uint amountOutUsed;
            //先计算pair从当前价格到price消耗amountIn的数量
            (amountInUsed, amountOutUsed, reserveInRet, reserveOutRet) =
                OrderBookLibrary.getAmountForMovePrice(tradeDir, reserveInRet, reserveOutRet, price, priceDecimal);
            //再计算本次移动价格获得的amountOut
            amountOutUsed = amountInUsed > amountInLeft ?
                OrderBookLibrary.getAmountOut(amountInLeft, reserveInRet, reserveOutRet) : amountOutUsed;
            amountOutGet += amountOutUsed;
            //再计算还剩下的amountIn
            if (amountInLeft > amountInUsed) {
                amountInLeft = amountInLeft - amountInUsed;
            }
            else { //amountIn消耗完了
                amountInLeft = 0;
                break;
            }

            //计算消耗掉一个价格的挂单需要的amountIn数量
            (uint amountInForTake, uint amountOutWithFee,) = OrderBookLibrary.getAmountOutForTakePrice(
                tradeDir, amountInLeft, price, priceDecimal, amount);
            amountOutGet += amountOutWithFee;
            if (amountInLeft > amountInForTake) {
                amountInLeft = amountInLeft - amountInForTake;
            }
            else {
                amountInLeft = 0;
                break;
            }

            (price, amount) = nextBook(orderDir, price);
        }
    }

    function getAmountInForMovePrice(address tokenOut, uint amountOutOffer, uint reserveIn, uint reserveOut)
    external
    view
    returns (uint amountInGet, uint amountOutLeft, uint reserveInRet, uint reserveOutRet) {
        (reserveInRet, reserveOutRet) = (reserveIn, reserveOut);
        uint orderDir = tradeDirection(tokenOut); // 订单方向与交易方向相反
        uint tradeDir = OrderBookLibrary.getOppositeDirection(orderDir);
        amountOutLeft = amountOutOffer;
        amountInGet = 0;
        (uint price, uint amount) = nextBook(orderDir, 0);
        while (price != 0) {
            uint amountInUsed;
            uint amountOutUsed;
            //先计算pair从当前价格到price消耗amountIn的数量
            (amountInUsed, amountOutUsed, reserveInRet, reserveOutRet) =
                OrderBookLibrary.getAmountForMovePrice(tradeDir, reserveInRet, reserveOutRet, price, priceDecimal);
            //再计算本次移动价格获得的amountOut
            amountInUsed = amountOutUsed > amountOutLeft ?
                OrderBookLibrary.getAmountIn(amountOutLeft, reserveInRet, reserveOutRet) : amountInUsed;
            amountInGet += amountInUsed;
            //再计算还剩下的amountIn
            if (amountOutLeft > amountOutUsed) {
                amountOutLeft = amountOutLeft - amountOutUsed;
            }
            else { //amountOut消耗完了
                amountOutLeft = 0;
                break;
            }

            //计算消耗掉一个价格的挂单需要的amountOut数量
            (uint amountInForTake, uint amountOutWithFee,) = OrderBookLibrary.getAmountInForTakePrice(tradeDir,
                amountOutLeft, price, priceDecimal, amount);
            amountInGet += amountInForTake;
            if (amountOutLeft > amountOutWithFee) {
                amountOutLeft = amountOutLeft - amountOutWithFee;
            }
            else {
                amountOutLeft = 0;
                break;
            }

            (price, amount) = nextBook(orderDir, price);
        }
    }

    function takeOrderWhenMovePrice(address tokenIn, uint amountIn, address to)
    external
    returns (uint amountAmmOut, address[] memory accounts, uint[] memory amounts) {
        (uint reserveIn, uint reserveOut) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);
        //先吃单再付款，需要保证只有pair可以调用
        require(msg.sender == pair, 'Hybridx OrderBook: invalid sender');

        //direction for tokenA swap to tokenB
        uint tradeDir = tradeDirection(tokenIn);
        uint orderDir = OrderBookLibrary.getOppositeDirection(tradeDir);
        uint amountInLeft = amountIn;

        (uint price, uint amount) = nextBook(orderDir, 0); // 订单方向与交易方向相反
        //只处理挂单，reserveIn/reserveOut只用来计算需要消耗的挂单数量和价格范围
        while (price != 0) {
            //先计算pair从当前价格到price消耗amountIn的数量
            {
                uint amountInUsed;
                uint amountOutUsed;
                (amountInUsed, amountOutUsed, reserveIn, reserveOut) =
                OrderBookLibrary.getAmountForMovePrice(
                    tradeDir,
                    reserveIn,
                    reserveOut,
                    price,
                    priceDecimal);
                if (amountInUsed > amountInLeft) {
                    amountAmmOut += OrderBookLibrary.getAmountOut(amountInLeft, reserveIn, reserveOut);
                    amountInLeft = 0;
                }
                else {
                    amountAmmOut += amountOutUsed;
                    amountInLeft = amountInLeft - amountInUsed;
                }

                if (amountInLeft == 0) {
                    break;
                }
            }

            {
                //消耗掉一个价格的挂单并返回实际需要的amountIn数量
                (uint amountInForTake, uint amountOutWithFee, address[] memory _accounts, uint[] memory _amounts) =
                    getAmountAndTakePrice(to, tradeDir, amountInLeft, price, priceDecimal, amount);
                amounts.extendUint(_amounts);
                accounts.extendAddress(_accounts);
                if (amountInLeft > amountInForTake) {
                    amountInLeft = amountInLeft - amountInForTake;
                    amountAmmOut += amountOutWithFee;
                }
                else { //amountIn消耗完了
                    amountAmmOut += OrderBookLibrary.getAmountOut(amountInLeft, reserveIn, reserveOut);
                    amountInLeft = 0;
                    break;
                }
            }

            (price, amount) = nextBook(orderDir, price);
        }

        if (amountInLeft > 0) {
            amountAmmOut +=  OrderBookLibrary.getAmountOut(amountInLeft, reserveIn, reserveOut);
        }
    }
}
