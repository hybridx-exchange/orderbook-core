pragma solidity =0.5.16;

import "./interfaces/IWETH.sol";
import './libraries/TransferHelper.sol';
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
    private
    returns (uint amountIn, uint amountOutWithFee, uint fee, address[] memory accounts, uint[] memory amounts) {
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
            (accounts, amounts, ) = _takeLimitOrder(LIMIT_SELL, amountOutWithFee, price);
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
            (accounts, amounts, ) = _takeLimitOrder(LIMIT_BUY, amountIn, price);
        }
    }

    function getAmountAndTakePrice(
        address to,
        uint direction,
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

    function _batchTransfer(address token, address[] memory accounts, uint[] memory amounts) internal {
        address WETH = IOrderBookFactory(factory).WETH();
        for(uint i=0; i<accounts.length; i++) {
            if (WETH == token){
                IWETH(WETH).withdraw(amounts[i]);
                TransferHelper.safeTransferETH( accounts[i], amounts[i]);
            }
            else {
                _safeTransfer(token, accounts[i], amounts[i]);
            }
        }
    }

    function _singleTransfer(address token, address to, uint amount) internal {
        address WETH = IOrderBookFactory(factory).WETH();
        if (token == WETH) {
            IWETH(WETH).withdraw(amount);
            TransferHelper.safeTransferETH(to, amount);
        }
        else{
            _safeTransfer(token, to, amount);
        }
    }

    function _ammMovePrice(
        uint direction,
        uint reserveIn,
        uint reserveOut,
        uint price,
        uint decimal,
        uint _amountLeft,
        uint _amountAmmIn,
        uint _amountAmmOut)
    private
    pure
    returns (uint amountLeft, uint amountAmmIn, uint amountAmmOut) {
        uint amountInUsed;
        uint amountOutUsed;
        (amountInUsed, amountOutUsed, reserveIn, reserveOut) =
        OrderBookLibrary.getAmountForAmmMovePrice(
            direction,
            reserveIn,
            reserveOut,
            price,
            decimal);
        if (amountInUsed > _amountLeft) {
            amountAmmIn = _amountAmmIn + _amountLeft;
            amountAmmOut = _amountAmmOut + OrderBookLibrary.getAmountOut(_amountLeft, reserveIn, reserveOut);
            amountLeft = 0;
        }
        else {
            amountAmmIn = _amountAmmIn + amountInUsed;
            amountAmmOut = _amountAmmOut + amountOutUsed;
            amountLeft = _amountLeft - amountInUsed;
        }
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
        (uint reserveIn, uint reserveOut) = OrderBookLibrary.getReserves(pair, quoteToken, baseToken);
        uint amountAmmIn;
        uint amountAmmOut;
        uint amountOrderBookOut;
        amountLeft = amountOffer;

        uint price = nextPrice(LIMIT_SELL, 0);
        uint amount = price != 0 ? listAgg(LIMIT_SELL, price) : 0;
        while (price != 0 && price <= targetPrice) {
            //skip if there is no liquidity in lp pool
            if (reserveIn > 0 && reserveOut > 0 && price != targetPrice) {
                (amountLeft, amountAmmIn, amountAmmOut) =
                    _ammMovePrice(LIMIT_BUY, reserveIn, reserveOut, price, priceDecimal,
                        amountLeft, amountAmmIn, amountAmmOut);
                if (amountLeft == 0) {
                    break;
                }
            }

            //take the order of price 'price'.
            (uint amountInForTake,
            uint amountOutWithFee,
            ,
            address[] memory accounts,
            uint[] memory amounts) =
                _getAmountAndTakePrice(LIMIT_SELL, amountLeft, price, priceDecimal, amount);
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
            (amountLeft, amountAmmIn, amountAmmOut) =
                _ammMovePrice(LIMIT_BUY, reserveIn, reserveOut, price, priceDecimal,
                    amountLeft, amountAmmIn, amountAmmOut);
        }

        if (amountAmmIn > 0) {
            _safeTransfer(quoteToken, pair, amountAmmIn);
            (uint amount0Out, uint amount1Out) = baseToken == IUniswapV2Pair(pair).token0() ?
                (uint(0), amountAmmOut) : (amountAmmOut, uint(0));
            address WETH = IOrderBookFactory(factory).WETH();
            if (WETH == baseToken) {
                IUniswapV2Pair(pair).swapOriginal(amount0Out, amount1Out, address(this), new bytes(0));
                IWETH(WETH).withdraw(amountAmmOut);
                TransferHelper.safeTransferETH(to, amountAmmOut);
            }
            else {
                IUniswapV2Pair(pair).swapOriginal(amount0Out, amount1Out, to, new bytes(0));
            }
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
        (uint reserveIn, uint reserveOut) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);
        amountLeft = amountOffer;
        uint amountAmmIn;
        uint amountAmmOut;
        uint amountOrderBookOut;

        uint price = nextPrice(LIMIT_BUY, 0);
        uint amount = price != 0 ? listAgg(LIMIT_BUY, price) : 0;
        while (price != 0 && price <= targetPrice) {
            //skip if there is no liquidity in lp pool
            if (reserveIn > 0 && reserveOut > 0 && price != targetPrice) {
                (amountLeft, amountAmmIn, amountAmmOut) =
                    _ammMovePrice(LIMIT_SELL, reserveIn, reserveOut, price, priceDecimal,
                        amountLeft, amountAmmIn, amountAmmOut);
                if (amountLeft == 0) {
                    break;
                }
            }

            //take the order of price 'price'.
            (uint amountInForTake,
            uint amountOutWithFee,
            ,
            address[] memory accounts,
            uint[] memory amounts) = _getAmountAndTakePrice(LIMIT_BUY, amountLeft, price, priceDecimal, amount);
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
        if (price < targetPrice && amountLeft > 0) {
            (amountLeft, amountAmmIn, amountAmmOut) =
                _ammMovePrice(LIMIT_SELL, reserveIn, reserveOut, targetPrice, priceDecimal,
                    amountLeft, amountAmmIn, amountAmmOut);
        }

        if (amountAmmIn > 0) {
            _safeTransfer(baseToken, pair, amountAmmIn);
            (uint amount0Out, uint amount1Out) = quoteToken == IUniswapV2Pair(pair).token0() ?
                (uint(0), amountAmmOut) : (amountAmmOut, uint(0));
            address WETH = IOrderBookFactory(factory).WETH();
            if (WETH == quoteToken) {
                IUniswapV2Pair(pair).swapOriginal(amount0Out, amount1Out, address(this), new bytes(0));
                IWETH(WETH).withdraw(amountAmmOut);
                TransferHelper.safeTransferETH(to, amountAmmOut);
            }
            else {
                IUniswapV2Pair(pair).swapOriginal(amount0Out, amount1Out, to, new bytes(0));
            }
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
        require(price > 0 && price % priceStep == 0, 'UniswapV2 OrderBook: Price Invalid');

        //get input amount of quote token for buy limit order
        uint balance = _getQuoteBalance();
        uint amountOffer = balance > quoteBalance ? balance - quoteBalance : 0;
        require(amountOffer >= minAmount, 'UniswapV2 OrderBook: Amount Invalid');

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
        require(price > 0 && price % priceStep == 0, 'UniswapV2 OrderBook: Price Invalid');

        //get input amount of base token for sell limit order
        uint balance = _getBaseBalance();
        uint amountOffer = balance > baseBalance ? balance - baseBalance : 0;
        require(amountOffer >= minAmount, 'UniswapV2 OrderBook: Amount Invalid');

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
        address token = o.orderType == 1 ? quoteToken : baseToken;
        _singleTransfer(token, o.to, o.amountRemain);

        //update token balance
        uint balance = IERC20(token).balanceOf(address(this));
        if (o.orderType == 1) quoteBalance = balance;
        else baseBalance = balance;

        emit OrderCanceled(o.owner, o.to, o.amountOffer, o.amountRemain, o.price, o.orderType);
    }

    function _takeLimitOrder(
        uint direction,
        uint amount,
        uint price)
    internal
    returns (address[] memory accounts, uint[] memory amounts, uint amountUsed) {
        uint amountLeft = amount;
        uint index;
        uint length = length(direction, price);
        accounts = new address[](length);
        amounts = new uint[](length);
        while (index < length && amountLeft > 0) {
            uint orderId = peek(direction, price);
            Order memory order = marketOrders[orderId];
            require(orderId == order.orderId && order.orderType == 1 && price == order.price,
                'UniswapV2 OrderBook: Order Invalid');
            accounts[index] = order.to;
            amounts[index] = amountLeft > order.amountRemain ? order.amountRemain : amountLeft;
            order.amountRemain = order.amountRemain - amounts[index];

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

            amountLeft = amountLeft - amounts[index++];
        }

        amountUsed = amount - amountLeft;
    }

    //take buy limit order
    function takeBuyLimitOrder(
        uint amount,
        uint price)
    external
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
            'UniswapV2 OrderBook: Order Exist');
        priceStep = newPriceStep;
    }

    //更新最小数量
    function minAmountUpdate(uint newMinAmount) external lock {
        require(priceLength(LIMIT_BUY) == 0 && priceLength(LIMIT_SELL) == 0,
            'UniswapV2 OrderBook: Order Exist');
        minAmount = newMinAmount;
    }

    function getAmountOutForMovePrice(address tokenIn, uint amountInOffer, uint reserveIn, uint reserveOut)
    external
    view
    returns (uint amountOutGet, uint amountInLeft, uint reserveInRet, uint reserveOutRet){
        //先吃单再付款，需要保证只有pair可以调用
        require(msg.sender == pair, 'UniswapV2 OrderBook: invalid sender');
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
            (amountInUsed, amountOutUsed, reserveInRet, reserveOutRet) = OrderBookLibrary.getAmountForAmmMovePrice(
                tradeDir, reserveInRet, reserveOutRet, price, priceDecimal);
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
            (uint amountInForTake, uint amountOutWithFee) = OrderBookLibrary.getAmountOutForTakePrice(
                orderDir, amountInLeft, price, priceDecimal, amount);
            amountOutGet += amountOutWithFee;
            if (amountInLeft > amountInForTake) {
                amountInLeft = amountInLeft - amountInForTake;
            }
            else{
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
            (amountInUsed, amountOutUsed, reserveInRet, reserveOutRet) = OrderBookLibrary.getAmountForAmmMovePrice(
                tradeDir, reserveInRet, reserveOutRet, price, priceDecimal);
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
            (uint amountInForTake, uint amountOutWithFee) = OrderBookLibrary.getAmountInForTakePrice(orderDir,
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
        require(msg.sender == pair, "UniswapV2 OrderBook: FORBIDDEN");

        //direction for tokenA swap to tokenB
        uint tradeDir = tradeDirection(tokenIn);
        require(tradeDir == LIMIT_SELL, "tradeDir != LIMIT_SELL");
        uint orderDir = OrderBookLibrary.getOppositeDirection(tradeDir);
        require(orderDir == LIMIT_BUY, "orderDir != LIMIT_BUY");
        uint amountInLeft = amountIn;

        (uint price, uint amount) = nextBook(orderDir, 0); // 订单方向与交易方向相反
        //只处理挂单，reserveIn/reserveOut只用来计算需要消耗的挂单数量和价格范围
        while (price != 0) {
            //先计算pair从当前价格到price消耗amountIn的数量
            {
                uint amountInUsed;
                uint amountOutUsed;
                (amountInUsed, amountOutUsed, reserveIn, reserveOut) =
                OrderBookLibrary.getAmountForAmmMovePrice(
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
                    getAmountAndTakePrice(to, orderDir, amountInLeft, price, priceDecimal, amount);
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
