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

    function _takeLimitOrder(
        uint direction,
        uint amountInOffer,
        uint amountOutWithFee,
        uint price)
    internal
    returns (address[] memory accountsTo, uint[] memory amountsTo) {
        uint amountLeft = amountOutWithFee;
        uint index;
        uint length = length(direction, price);
        address[] memory accountsAll = new address[](length);
        uint[] memory amountsOut = new uint[](length);
        while (index < length && amountLeft > 0) {
            uint orderId = peek(direction, price);
            if (orderId == 0) break;
            Order memory order = marketOrders[orderId];
            require(orderId == order.orderId && order.orderType == direction && price == order.price,
                'Hybridx OrderBook: Order Invalid');
            accountsAll[index] = order.to;
            uint amountTake = amountLeft > order.amountRemain ? order.amountRemain : amountLeft;
            order.amountRemain = order.amountRemain - amountTake;
            amountsOut[index] = amountTake;

            amountLeft = amountLeft - amountTake;
            if (order.amountRemain != 0) {
                marketOrders[orderId].amountRemain = order.amountRemain;
                emit OrderUpdate(order.owner, order.to, order.price, order.amountOffer, order
                    .amountRemain, order.orderType);
                index++;
                break;
            }

            _removeFrontLimitOrderOfQueue(order);

            emit OrderClosed(order.owner, order.to, order.price, order.amountOffer, order
                .amountRemain, order.orderType);
            index++;
        }

        if (index > 0) {
            accountsTo = Arrays.subAddress(accountsAll, index);
            amountsTo = new uint[](index);
            require(amountsTo.length == amountsOut.length);
            for (uint i; i<index; i++) {
                amountsTo[i] = amountInOffer.mul(amountsOut[i]).div(amountOutWithFee);
            }
        }
    }

    function _getAmountAndTake(
        uint direction,
        uint amountInOffer,
        uint price,
        uint orderAmount)
    internal
    returns (uint amountIn, uint amountOutWithFee, uint fee, address[] memory accountsTo, uint[] memory amountsTo) {
        (amountIn, amountOutWithFee, fee) = OrderBookLibrary.getAmountOutForTakePrice
            (direction, amountInOffer, price, priceDecimal, orderAmount);
        (accountsTo, amountsTo) = _takeLimitOrder
            (OrderBookLibrary.getOppositeDirection(direction), amountIn, amountOutWithFee, price);
    }

    function _getAmountAndPay(
        address to,
        uint direction,//TRADE DIRECTION
        uint amountInOffer,
        uint price,
        uint orderAmount,
        address[] memory _accounts,
        uint[] memory _amounts)
    internal
    returns (uint amountIn, uint amountOutWithFee, address[] memory accounts, uint[] memory amounts) {
        (amountIn, amountOutWithFee, , accounts, amounts) =
            _getAmountAndTake(direction, amountInOffer, price, orderAmount);
        amounts.extendUint(_amounts);
        accounts.extendAddress(_accounts);

        //当token为weth时，外部调用的时候直接将weth转出
        address tokenOut = direction == LIMIT_BUY ? baseToken : quoteToken;
        _safeTransfer(tokenOut, to, amountOutWithFee);
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
        uint[] memory reserves = new uint[](4);//[reserveBase, reserveQuote, reserveBaseTmp, reserveQuoteTmp]
        (reserves[0], reserves[1]) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);
        (reserves[2], reserves[3]) = (reserves[0], reserves[1]);
        bool liquidityExists = reserves[0] > 0 && reserves[1] > 0;
        uint amountAmmBase;
        uint amountAmmQuote;
        uint amountOrderBookOut;
        amountLeft = amountOffer;

        uint price = nextPrice(LIMIT_SELL, 0);
        while (price != 0 && price <= targetPrice) {
            uint amountAmmLeft = amountLeft;
            //skip if there is no liquidity in lp pool
            if (liquidityExists) {
                (amountAmmLeft, amountAmmBase, amountAmmQuote, reserves[2], reserves[3]) =
                    OrderBookLibrary.getAmountForMovePrice(LIMIT_BUY, amountLeft,
                        reserves[0], reserves[1], price, priceDecimal);
                if (amountAmmLeft == 0) {
                    amountLeft = 0; //avoid getAmountForMovePrice recalculation
                    break;
                }
            }

            uint amount = listAgg(LIMIT_SELL, price);
            //take the order of price 'price'.
            (uint amountInForTake,
            uint amountOutWithFee,,
            address[] memory accounts,
            uint[] memory amounts) = _getAmountAndTake(LIMIT_BUY, amountAmmLeft, price, amount);
            amountOrderBookOut += amountOutWithFee;
            _batchTransfer(quoteToken, accounts, amounts);

            if (amountInForTake == amountAmmLeft) {  //break if there is no amount left.
                amountLeft = 0;  //avoid getAmountForMovePrice recalculation
                break;
            } else {
                amountLeft = amountLeft.sub(amountInForTake);
            }

            price = nextPrice(LIMIT_SELL, price);
        }

        // send the user for take all limit order's amount.
        if (amountOrderBookOut > 0) {
            _singleTransfer(baseToken, to, amountOrderBookOut);
        }

        // swap to target price when there is no limit order less than the target price
        if (liquidityExists && amountLeft > 0 && price != targetPrice) {
            (amountLeft, amountAmmBase, amountAmmQuote, reserves[2], reserves[3]) =
                OrderBookLibrary.getAmountForMovePrice(LIMIT_BUY, amountLeft,
                    reserves[0], reserves[1], targetPrice, priceDecimal);
        }

        if (amountAmmQuote > 0) {
            if (amountLeft > 0) {
                (amountLeft, amountAmmQuote,) =
                    OrderBookLibrary.getFixAmountForMovePriceUp(amountLeft, amountAmmQuote, reserves[2], reserves[3],
                        targetPrice, priceDecimal);
            }

            _ammSwapPrice(to, quoteToken, baseToken, amountAmmQuote, amountAmmBase);
            require(amountLeft == 0 || getPrice() >= targetPrice, "Hybridx OrderBook: Buy price mismatch");
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
        uint[] memory reserves = new uint[](4);//[reserveBase, reserveQuote, reserveBaseTmp, reserveQuoteTmp]
        (reserves[0], reserves[1]) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);
        (reserves[2], reserves[3]) = (reserves[0], reserves[1]);
        amountLeft = amountOffer;
        bool liquidityExists = reserves[0] > 0 && reserves[1] > 0;
        uint amountAmmBase;
        uint amountAmmQuote;
        uint amountOrderBookOut;

        uint price = nextPrice(LIMIT_BUY, 0);
        while (price != 0 && price >= targetPrice) {
            uint amountAmmLeft = amountLeft;
            //skip if there is no liquidity in lp pool
            if (liquidityExists) {
                (amountAmmLeft, amountAmmBase, amountAmmQuote, reserves[2], reserves[3]) =
                    OrderBookLibrary.getAmountForMovePrice(LIMIT_SELL, amountLeft,
                        reserves[0], reserves[1], price, priceDecimal);
                if (amountAmmLeft == 0) {
                    amountLeft = 0;  //avoid getAmountForMovePrice recalculation
                    break;
                }
            }

            uint amount = listAgg(LIMIT_BUY, price);
            //take the order of price 'price'.
            (uint amountInForTake,
            uint amountOutWithFee,,
            address[] memory accounts,
            uint[] memory amounts) = _getAmountAndTake(LIMIT_SELL, amountAmmLeft, price, amount);
            amountOrderBookOut += amountOutWithFee;
            _batchTransfer(baseToken, accounts, amounts);

            if (amountInForTake == amountAmmLeft) { //break if there is no amount left.
                amountLeft = 0;  //avoid getAmountForMovePrice recalculation
                break;
            } else {
                amountLeft = amountLeft.sub(amountInForTake);
            }

            price = nextPrice(LIMIT_BUY, price);
        }

        // send the user for take all limit order's amount.
        if (amountOrderBookOut > 0) {
            _singleTransfer(quoteToken, to, amountOrderBookOut);
        }

        // swap to target price when there is no limit order less than the target price
        if (liquidityExists && amountLeft > 0 && price != targetPrice) {
            (amountLeft, amountAmmBase, amountAmmQuote, reserves[2], reserves[3]) =
                OrderBookLibrary.getAmountForMovePrice(LIMIT_SELL, amountLeft,
                    reserves[0], reserves[1], targetPrice, priceDecimal);
        }

        if (amountAmmBase > 0) {
            if (amountLeft > 0) {
                (amountLeft, amountAmmBase,) =
                    OrderBookLibrary.getFixAmountForMovePriceDown(amountLeft, amountAmmBase, reserves[2], reserves[3],
                        targetPrice, priceDecimal);
            }

            _ammSwapPrice(to, baseToken, quoteToken, amountAmmBase, amountAmmQuote);
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

        IUniswapV2Pair(pair).skim(user);
        uint amountRemain = _movePriceUp(amountOffer, price, to);
        if (amountRemain != 0) {
            orderId = _addLimitOrder(user, to, amountOffer, amountRemain, price, LIMIT_BUY);
            emit OrderCreated(user, to, amountOffer, amountRemain, price, LIMIT_BUY);
        }

        //update balance
        _updateBalance();
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
        uint minQuoteAmount = OrderBookLibrary.getSellAmountWithPrice(minAmount, price, priceDecimal);
        require(amountOffer >= minQuoteAmount, 'Hybridx OrderBook: Amount Invalid');

        IUniswapV2Pair(pair).skim(user);
        uint amountRemain = _movePriceDown(amountOffer, price, to);
        if (amountRemain != 0) {
            orderId = _addLimitOrder(user, to, amountOffer, amountRemain, price, LIMIT_SELL);
            emit OrderCreated(user, to, amountOffer, amountRemain, price, LIMIT_SELL);
        }

        //update balance
        _updateBalance();
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

    /*******************************************************************************************************
                                    called by uniswap v2 pair and router
     *******************************************************************************************************/
    function getAmountOutForMovePrice(address tokenIn, uint amountInOffer)
    external
    view
    returns (uint amountOutGet) {
        (uint reserveBase, uint reserveQuote) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);
        uint tradeDir = tradeDirection(tokenIn);
        uint orderDir = OrderBookLibrary.getOppositeDirection(tradeDir); // 订单方向与交易方向相反
        uint amountInLeft = amountInOffer;
        amountOutGet = 0;
        (uint price, uint amount) = nextBook(orderDir, 0);
        while (price != 0) {
            //先计算pair从当前价格到price消耗amountIn的数量
            (uint amountAmmLeft,,,,) =
                OrderBookLibrary.getAmountForMovePrice(tradeDir, amountInLeft, reserveBase, reserveQuote, price,
                    priceDecimal);
            if (amountAmmLeft == 0) {
                break;
            }

            //计算消耗掉一个价格的挂单需要的amountIn数量
            (uint amountInForTake, uint amountOutWithFee,) = OrderBookLibrary.getAmountOutForTakePrice(
                tradeDir, amountAmmLeft, price, priceDecimal, amount);
            amountOutGet += amountOutWithFee;
            amountInLeft = amountInLeft.sub(amountInForTake);
            if (amountInForTake == amountAmmLeft) {
                break;
            }

            (price, amount) = nextBook(orderDir, price);
        }

        if (amountInLeft > 0) {
            amountOutGet += tradeDir == LIMIT_BUY ?
                OrderBookLibrary.getAmountOut(amountInLeft, reserveQuote, reserveBase) :
                OrderBookLibrary.getAmountOut(amountInLeft, reserveBase, reserveQuote);
        }
    }

    function getAmountInForMovePrice(address tokenOut, uint amountOutOffer)
    external
    view
    returns (uint amountInGet) {
        (uint reserveBase, uint reserveQuote) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);
        uint orderDir = tradeDirection(tokenOut); // 订单方向与交易方向相反
        uint tradeDir = OrderBookLibrary.getOppositeDirection(orderDir);
        uint amountOutLeft = amountOutOffer;
        amountInGet = 0;
        (uint price, uint amount) = nextBook(orderDir, 0);
        while (price != 0) {
            //先计算pair从当前价格到price消耗amountIn的数量
            (uint amountAmmLeft,,,,) =
            OrderBookLibrary.getAmountForMovePriceWithAmountOut(tradeDir, amountOutLeft, reserveBase, reserveQuote,
                price, priceDecimal);
            if (amountAmmLeft == 0) {
                break;
            }

            //计算消耗掉一个价格的挂单需要的amountOut数量
            (uint amountInForTake, uint amountOutWithFee,) = OrderBookLibrary.getAmountInForTakePrice(tradeDir,
                amountAmmLeft, price, priceDecimal, amount);
            amountInGet += amountInForTake;
            amountOutLeft = amountOutLeft.sub(amountOutWithFee);
            if (amountOutWithFee == amountAmmLeft) {
                break;
            }

            (price, amount) = nextBook(orderDir, price);
        }

        if (amountOutLeft > 0) {
            amountInGet += tradeDir == LIMIT_BUY ?
                OrderBookLibrary.getAmountIn(amountOutLeft, reserveQuote, reserveBase) :
                OrderBookLibrary.getAmountIn(amountOutLeft, reserveBase, reserveQuote);
        }
    }

    function takeOrderWhenMovePrice(address tokenIn, uint amountIn, address to)
    external
    lock
    returns (uint amountOut, address[] memory accounts, uint[] memory amounts) {
        //先吃单再付款，需要保证只有pair可以调用
        require(msg.sender == pair, 'Hybridx OrderBook: invalid sender');
        uint[] memory reserves = new uint[](2);//[reserveBase, reserveQuote]
        (reserves[0], reserves[1]) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);

        //direction for tokenA swap to tokenB
        uint tradeDir = tradeDirection(tokenIn);
        uint orderDir = OrderBookLibrary.getOppositeDirection(tradeDir);

        (uint price, uint amount) = nextBook(orderDir, 0); // 订单方向与交易方向相反
        //只处理挂单，reserveIn/reserveOut只用来计算需要消耗的挂单数量和价格范围
        while (price != 0) {
            //先计算pair从当前价格到price消耗的数量
            (uint amountAmmLeft,,,,) =
            OrderBookLibrary.getAmountForMovePrice(
                tradeDir,
                amountIn,
                reserves[0],
                reserves[1],
                price,
                priceDecimal);
            if (amountAmmLeft == 0) {
                break;
            }

            //消耗掉一个价格的挂单并返回实际需要的amountIn数量
            uint amountInForTake;
            uint amountOutWithFee;
            (amountInForTake, amountOutWithFee, accounts, amounts) =
                _getAmountAndPay(to, tradeDir, amountAmmLeft, price, amount, accounts, amounts);
            amountOut += amountOutWithFee;
            amountIn = amountIn.sub(amountInForTake);
            if (amountInForTake == amountAmmLeft) {
                break;
            }

            (price, amount) = nextBook(orderDir, price);
        }

        if (amountIn > 0) {
            amountOut += tradeDir == LIMIT_BUY ?
                OrderBookLibrary.getAmountOut(amountIn, reserves[1], reserves[0]) :
                OrderBookLibrary.getAmountOut(amountIn, reserves[0], reserves[1]);
        }
    }
}
