pragma solidity =0.5.16;

import "./interfaces/IOrderBook.sol";
import "./libraries/Arrays.sol";
import "./OrderBookBase.sol";

contract OrderBook is IOrderBook, OrderBookBase {
    using SafeMath for uint;
    using SafeMath for uint112;

    function() external payable {
    }

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
            require(amountsTo.length <= amountsOut.length, "Index Invalid");
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
    returns (uint amountIn, uint amountOutWithFee, uint communityFee,
        address[] memory accountsTo, uint[] memory amountsTo) {
        (amountIn, amountOutWithFee, communityFee) = OrderBookLibrary.getAmountOutForTakePrice
            (direction, amountInOffer, price, baseDecimal, protocolFeeRate, subsidyFeeRate, orderAmount);
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
    returns (uint amountIn, uint amountOutWithSubsidyFee, address[] memory accounts, uint[] memory amounts) {
        uint amountOutWithFee;
        uint communityFee;
        (amountIn, amountOutWithFee, communityFee, accounts, amounts) =
            _getAmountAndTake(direction, amountInOffer, price, orderAmount);
        amounts = Arrays.extendUint(amounts, _amounts);
        accounts = Arrays.extendAddress(accounts, _accounts);
        amountOutWithSubsidyFee = amountOutWithFee.sub(communityFee);

        //???token???weth????????????????????????????????????weth??????
        address tokenOut = direction == LIMIT_BUY ? baseToken : quoteToken;
        _safeTransfer(tokenOut, to, amountOutWithSubsidyFee);
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
    internal
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
                        reserves[0], reserves[1], price, baseDecimal);
                if (amountAmmLeft == 0) {
                    amountLeft = 0; //avoid getAmountForMovePrice recalculation
                    break;
                }
            }

            uint amount = listAgg(LIMIT_SELL, price);
            //take the order of price 'price'.
            (uint amountInForTake,
            uint amountOutWithFee,
            uint communityFee,
            address[] memory accounts,
            uint[] memory amounts) = _getAmountAndTake(LIMIT_BUY, amountAmmLeft, price, amount);
            amountOrderBookOut += amountOutWithFee.sub(communityFee);
            _batchTransfer(quoteToken, accounts, amounts);

            if (amountInForTake == amountAmmLeft) {  //break if there is no amount left.
                amountLeft = 0;  //avoid getAmountForMovePrice recalculation
                break;
            } else {
                amountLeft = amountLeft.sub(amountInForTake);
            }

            price = nextPrice2(LIMIT_SELL, price);
        }

        // send the user for take all limit order's amount.
        if (amountOrderBookOut > 0) {
            _singleTransfer(baseToken, to, amountOrderBookOut);
        }

        // swap to target price when there is no limit order less than the target price
        if (liquidityExists && amountLeft > 0 && price != targetPrice) {
            (amountLeft, amountAmmBase, amountAmmQuote, reserves[2], reserves[3]) =
                OrderBookLibrary.getAmountForMovePrice(LIMIT_BUY, amountLeft,
                    reserves[0], reserves[1], targetPrice, baseDecimal);
        }

        if (amountAmmQuote > 0) {
            if (amountLeft > 0) {
                (amountLeft, amountAmmQuote,) =
                    OrderBookLibrary.getFixAmountForMovePriceUp(amountLeft, amountAmmQuote, reserves[2], reserves[3],
                        targetPrice, baseDecimal);
            }

            _ammSwapPrice(to, quoteToken, baseToken, amountAmmQuote, amountAmmBase);
            require(amountLeft == 0 || getPrice() >= targetPrice, "Buy price mismatch");
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
    internal
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
                        reserves[0], reserves[1], price, baseDecimal);
                if (amountAmmLeft == 0) {
                    amountLeft = 0;  //avoid getAmountForMovePrice recalculation
                    break;
                }
            }

            uint amount = listAgg(LIMIT_BUY, price);
            //take the order of price 'price'.
            (uint amountInForTake,
            uint amountOutWithFee,
            uint communityFee,
            address[] memory accounts,
            uint[] memory amounts) = _getAmountAndTake(LIMIT_SELL, amountAmmLeft, price, amount);
            amountOrderBookOut += amountOutWithFee.sub(communityFee);
            _batchTransfer(baseToken, accounts, amounts);

            if (amountInForTake == amountAmmLeft) { //break if there is no amount left.
                amountLeft = 0;  //avoid getAmountForMovePrice recalculation
                break;
            } else {
                amountLeft = amountLeft.sub(amountInForTake);
            }

            price = nextPrice2(LIMIT_BUY, price);
        }

        // send the user for take all limit order's amount.
        if (amountOrderBookOut > 0) {
            _singleTransfer(quoteToken, to, amountOrderBookOut);
        }

        // swap to target price when there is no limit order less than the target price
        if (liquidityExists && amountLeft > 0 && price != targetPrice) {
            (amountLeft, amountAmmBase, amountAmmQuote, reserves[2], reserves[3]) =
                OrderBookLibrary.getAmountForMovePrice(LIMIT_SELL, amountLeft,
                    reserves[0], reserves[1], targetPrice, baseDecimal);
        }

        if (amountAmmBase > 0) {
            if (amountLeft > 0) {
                (amountLeft, amountAmmBase,) =
                    OrderBookLibrary.getFixAmountForMovePriceDown(amountLeft, amountAmmBase, reserves[2], reserves[3],
                        targetPrice, baseDecimal);
            }

            _ammSwapPrice(to, baseToken, quoteToken, amountAmmBase, amountAmmQuote);
            require(amountLeft == 0 || getPrice() <= targetPrice, "sell to target failed");
        }
    }

    //limit order for buy base token with quote token
    function createBuyLimitOrder(
        address user,
        uint price,
        address to)
    external
    lock
    returns (uint orderId) {
        require(price > 0 && price % priceStep == 0, 'Price Invalid');
        require(OrderBookLibrary.getUniswapV2OrderBookFactory(factory) == factory,
            'OrderBook unconnected');

        //get input amount of quote token for buy limit order
        uint balance = _getQuoteBalance();
        uint amountOffer = balance > quoteBalance ? balance - quoteBalance : 0;
        uint minQuoteAmount = OrderBookLibrary.getQuoteAmountWithBaseAmountAtPrice(minAmount, price, baseDecimal);
        require(amountOffer >= minQuoteAmount, 'Amount Invalid');

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
        require(price > 0 && (price % priceStep) == 0, 'Price Invalid');
        require(OrderBookLibrary.getUniswapV2OrderBookFactory(factory) == factory,
            'OrderBook unconnected');

        //get input amount of base token for sell limit order
        uint balance = _getBaseBalance();
        uint amountOffer = balance > baseBalance ? balance - baseBalance : 0;
        require(amountOffer >= minAmount, 'Amount Invalid');

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
        require(o.owner == msg.sender, 'Owner Invalid');

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
    returns (uint amountOutGet, uint nextReserveBase, uint nextReserveQuote) {
        (uint reserveBase, uint reserveQuote) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);
        uint tradeDir = tradeDirection(tokenIn);
        uint orderDir = OrderBookLibrary.getOppositeDirection(tradeDir); // ?????????????????????????????????
        uint amountInLeft = amountInOffer;
        amountOutGet = 0;
        (uint price, uint amount) = nextBook(orderDir, 0);
        while (price != 0) {
            //?????????pair??????????????????price??????amountIn?????????
            uint amountAmmLeft;
            (amountAmmLeft,,, nextReserveBase, nextReserveQuote) =
                OrderBookLibrary.getAmountForMovePrice(tradeDir, amountInLeft, reserveBase, reserveQuote, price,
                    baseDecimal);
            if (amountAmmLeft == 0) {
                break;
            }

            //?????????????????????????????????????????????amountIn??????
            (uint amountInForTake, uint amountOutWithFee, uint communityFee) = OrderBookLibrary.getAmountOutForTakePrice(
                tradeDir, amountAmmLeft, price, baseDecimal, protocolFeeRate, subsidyFeeRate, amount);
            amountOutGet += amountOutWithFee.sub(communityFee);
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
    returns (uint amountInGet, uint nextReserveBase, uint nextReserveQuote) {
        (uint reserveBase, uint reserveQuote) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);
        uint orderDir = tradeDirection(tokenOut); // ?????????????????????????????????
        uint tradeDir = OrderBookLibrary.getOppositeDirection(orderDir);
        uint amountOutLeft = amountOutOffer;
        amountInGet = 0;
        (uint price, uint amount) = nextBook(orderDir, 0);
        while (price != 0) {
            //?????????pair??????????????????price??????amountIn?????????
            uint amountAmmLeft;
            (amountAmmLeft,,, nextReserveBase, nextReserveQuote) =
            OrderBookLibrary.getAmountForMovePriceWithAmountOut(tradeDir, amountOutLeft, reserveBase, reserveQuote,
                price, baseDecimal);
            if (amountAmmLeft == 0) {
                break;
            }

            //?????????????????????????????????????????????amountOut??????
            (uint amountInForTake, uint amountOutWithFee, uint communityFee) = OrderBookLibrary.getAmountInForTakePrice
                (tradeDir, amountAmmLeft, price, baseDecimal, protocolFeeRate, subsidyFeeRate, amount);
            amountInGet += amountInForTake.add(1);
            amountOutLeft = amountOutLeft.sub(amountOutWithFee.sub(communityFee));
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
    returns (uint amountOutLeft, address[] memory accounts, uint[] memory amounts) {
        //???????????????????????????????????????pair????????????
        require(msg.sender == pair, 'invalid sender');
        uint[] memory reserves = new uint[](2);//[reserveBase, reserveQuote]
        (reserves[0], reserves[1]) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);

        //direction for tokenA swap to tokenB
        uint tradeDir = tradeDirection(tokenIn);
        uint orderDir = OrderBookLibrary.getOppositeDirection(tradeDir);

        (uint price, uint amount) = nextBook(orderDir, 0); // ?????????????????????????????????
        //??????????????????reserveIn/reserveOut?????????????????????????????????????????????????????????
        while (price != 0) {
            //?????????pair??????????????????price???????????????
            (uint amountAmmLeft,,,,) =
            OrderBookLibrary.getAmountForMovePrice(
                tradeDir,
                amountIn,
                reserves[0],
                reserves[1],
                price,
                baseDecimal);
            if (amountAmmLeft == 0) {
                break;
            }

            //??????????????????????????????????????????????????????amountIn??????
            uint amountInForTake;
            (amountInForTake,, accounts, amounts) =
                _getAmountAndPay(to, tradeDir, amountAmmLeft, price, amount, accounts, amounts);
            amountIn = amountIn.sub(amountInForTake);
            if (amountInForTake == amountAmmLeft) {
                break;
            }

            (price, amount) = nextBook2(orderDir, price);
        }

        //??????balance
        _updateBalance();

        if (amountIn > 0) {
            amountOutLeft += tradeDir == LIMIT_BUY ?
                OrderBookLibrary.getAmountOut(amountIn, reserves[1], reserves[0]) :
                OrderBookLibrary.getAmountOut(amountIn, reserves[0], reserves[1]);
        }
    }
}
