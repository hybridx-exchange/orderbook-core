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
    internal
    returns (uint amountIn, uint amountOutWithFee, address[] memory accounts, uint[] memory amounts) {
        if (direction == LIMIT_BUY) { //buy (quoteToken == tokenIn)  用tokenIn（usdc)换tokenOut(btc)
            //amountOut = amountInOffer / price
            uint amountOut = OrderBookLibrary.getAmountInWithPrice(amountInOffer, price, decimal);
            if (amountOut.mul(1000) <= orderAmount.mul(997)) { //只吃掉一部分: amountOut > amountOffer * (1-0.3%)
                (amountIn, amountOutWithFee) = (amountInOffer, amountOut);
            }
            else {
                uint amountOutWithoutFee = orderAmount.mul(997) / 1000;//吃掉所有
                //amountIn = amountOutWithoutFee * price
                (amountIn, amountOutWithFee) = (OrderBookLibrary.getAmountOutWithPrice(amountOutWithoutFee, price, decimal),
                    orderAmount);
            }
            (accounts, amounts, ) = _takeLimitOrder(LIMIT_SELL, amountOutWithFee, price);
        }
        else if (direction == LIMIT_SELL) { //sell (quoteToken == tokenOut) 用tokenIn(btc)换tokenOut(usdc)
            //amountOut = amountInOffer * price
            uint amountOut = OrderBookLibrary.getAmountInWithPrice(amountInOffer, price, decimal);
            if (amountOut.mul(1000) <= orderAmount.mul(997)) { //只吃掉一部分: amountOut > amountOffer * (1-0.3%)
                (amountIn, amountOutWithFee) = (amountInOffer, amountOut);
            }
            else {
                uint amountOutWithoutFee = orderAmount.mul(997) / 1000;
                //amountIn = amountOutWithoutFee / price
                (amountIn, amountOutWithFee) = (OrderBookLibrary.getAmountOutWithPrice(amountOutWithoutFee, price,
                    decimal), orderAmount);
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
        (amountIn, amountOutWithFee, accounts, amounts) =
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

    //使用特定数量的token将价格向上移动到特定值--具体执行放到UniswapV2Pair里面, 在这里需要考虑当前价格到目标价格之间的挂单，amm中的分段只用于计算，实际交易一次性完成，不分段
    function _movePriceUp(
        uint amountOffer,
        uint targetPrice,
        address to)
    private
    returns (uint amountLeft) {
        (uint reserveOut, uint reserveIn,) = getReserves();
        uint amountAmmIn;
        uint amountAmmOut;
        uint amountOut;
        amountLeft = amountOffer;

        uint price = nextPrice(LIMIT_SELL, 0);
        uint amount = price != 0 ? listAgg(LIMIT_SELL, price) : 0;
        while (price != 0 && price <= targetPrice) {
            if (reserveIn > 0 && reserveOut > 0) {//LP没有流动性直接跳过
                //先计算pair从当前价格到price消耗amountIn的数量
                uint amountInUsed;
                uint amountOutUsed;
                (amountInUsed, amountOutUsed, reserveIn, reserveOut) =
                    OrderBookLibrary.getAmountForMovePrice(
                        LIMIT_BUY,
                        reserveIn,
                        reserveOut,
                        price,
                        priceDecimal);
                if (amountInUsed > amountLeft) {
                    amountAmmIn += amountLeft;
                    amountAmmOut += OrderBookLibrary.getAmountOut(amountLeft, reserveIn, reserveOut);
                    amountLeft = 0;
                }
                else {
                    amountAmmIn += amountInUsed;
                    amountAmmOut += amountOutUsed;
                    amountLeft = amountLeft - amountInUsed;
                }

                if (amountLeft == 0) {
                    break;
                }
            }

            //消耗掉一个价格的挂单并返回实际需要的amountIn数量
            (uint amountInForTake, uint amountOutWithFee, address[] memory accounts, uint[] memory amounts) =
                _getAmountAndTakePrice(LIMIT_SELL, amountLeft, price, priceDecimal, amount);
            amountOut += amountOutWithFee;

            //给对应数量的tokenIn发送给对应的账号
            _batchTransfer(quoteToken, accounts, amounts);

            amountLeft = amountInForTake < amountLeft ? amountLeft - amountInForTake : 0;
            if (amountLeft == 0) { //amountIn消耗完了
                break;
            }

            price = nextPrice(LIMIT_SELL, price);
            amount = price != 0 ? listAgg(LIMIT_SELL, price) : 0;
        }

        //一次性将吃单获得的数量转给用户
        if (amountOut > 0) {//当token为weth时，需要将weth转为eth
            _singleTransfer(baseToken, to, amountOut);
        }

        if (price < targetPrice && amountLeft > 0){//处理挂单之外的价格范围
            uint amountInUsed;
            uint amountOutUsed;
            (amountInUsed, amountOutUsed, reserveIn, reserveOut) =
            OrderBookLibrary.getAmountForMovePrice(
                LIMIT_BUY,
                reserveIn,
                reserveOut,
                targetPrice,
                priceDecimal);
            if (amountInUsed > amountLeft) {
                amountAmmIn += amountLeft;
                amountAmmOut += OrderBookLibrary.getAmountOut(amountLeft, reserveIn, reserveOut);
                amountLeft = 0;
            }
            else {
                amountAmmIn += amountInUsed;
                amountAmmOut += amountOutUsed;
                amountLeft = amountLeft - amountInUsed;
            }
        }

        if (amountAmmIn > 0) {//向pair转账
            _safeTransfer(quoteToken, pair, amountAmmIn);
            //将当前价格移动到目标价格并最多消耗amountLeft
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

    //使用特定数量的token将价格向上移动到特定值--具体执行放到UniswapV2Pair里面, 在这里需要考虑当前价格到目标价格之间的挂单
    function _movePriceDown(
        uint amountOffer,
        uint targetPrice,
        address to)
    private
    returns (uint amountLeft) {
        (uint reserveIn, uint reserveOut,) = getReserves();
        amountLeft = amountOffer;
        uint amountAmmIn;
        uint amountAmmOut;
        uint amountOut;

        uint price = nextPrice(LIMIT_BUY, 0);
        uint amount = price != 0 ? listAgg(LIMIT_BUY, price) : 0;
        while (price != 0 && price <= targetPrice) {
            if (reserveIn > 0 && reserveOut > 0) {//LP没有流动性直接跳过
                //先计算pair从当前价格到price消耗amountIn的数量
                uint amountInUsed;
                uint amountOutUsed;
                (amountInUsed, amountOutUsed, reserveIn, reserveOut) =
                OrderBookLibrary.getAmountForMovePrice(
                    LIMIT_SELL,
                    reserveIn,
                    reserveOut,
                    price,
                    priceDecimal);
                if (amountInUsed > amountLeft) {
                    amountAmmIn += amountLeft;
                    amountAmmOut += OrderBookLibrary.getAmountOut(amountLeft, reserveIn, reserveOut);
                    amountLeft = 0;
                }
                else {
                    amountAmmIn += amountInUsed;
                    amountAmmOut += amountOutUsed;
                    amountLeft = amountLeft - amountInUsed;
                }

                if (amountLeft == 0) {
                    break;
                }
            }

            //消耗掉一个价格的挂单并返回实际需要的amountIn数量
            (uint amountInForTake, uint amountOutWithFee, address[] memory accounts, uint[] memory amounts) =
                _getAmountAndTakePrice(LIMIT_BUY, amountLeft, price, priceDecimal, amount);
            amountOut += amountOutWithFee;

            //给对应数量的tokenIn发送给对应的账号
            _batchTransfer(baseToken, accounts, amounts);

            amountLeft = amountInForTake < amountLeft ? amountLeft - amountInForTake : 0;
            if (amountLeft == 0) { //amountIn消耗完了
                break;
            }

            price = nextPrice(LIMIT_BUY, price);
            amount = price != 0 ? listAgg(LIMIT_BUY, price) : 0;
        }

        if (amountOut > 0){
            _singleTransfer(quoteToken, to, amountOut);
        }

        if (price < targetPrice && amountLeft > 0){//处理挂单之外的价格范围
            uint amountInUsed;
            uint amountOutUsed;
            (amountInUsed, amountOutUsed, reserveIn, reserveOut) =
                OrderBookLibrary.getAmountForMovePrice(
                    LIMIT_SELL,
                    reserveIn,
                    reserveOut,
                    targetPrice,
                    priceDecimal);
            if (amountInUsed > amountLeft) {
                amountAmmIn += amountLeft;
                amountAmmOut += OrderBookLibrary.getAmountOut(amountLeft, reserveIn, reserveOut);
                amountLeft = 0;
            }
            else {
                amountAmmIn += amountInUsed;
                amountAmmOut += amountOutUsed;
                amountLeft = amountLeft - amountInUsed;
            }
        }

        if (amountAmmIn > 0){//向pair转账
            _safeTransfer(baseToken, pair, amountAmmIn);
            //将当前价格移动到目标价格并最多消耗amountLeft
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

    //创建限价买订单
    function createBuyLimitOrder(
        address user,
        uint price,
        address to)
    external
    lock
    returns (uint orderId) {
        require(price > 0 && price % priceStep == 0, 'UniswapV2 OrderBook: Price Invalid');

        //需要先将token转移到order book合约(在router中执行), 以免与pair中的token混合
        uint balance = IERC20(quoteToken).balanceOf(address(this));
        uint amountOffer = balance > quoteBalance ? balance - quoteBalance : 0;
        require(amountOffer >= minAmount, 'UniswapV2 OrderBook: Amount Invalid');
        //更新quote余额
        quoteBalance = balance;

        //先在流动性池将价格拉到挂单价，同时还需要吃掉价格范围内的反方向挂单
        uint amountRemain = _movePriceUp(amountOffer, price, to);
        if (amountRemain != 0) {
            //未成交的部分生成限价买单
            orderId = _addLimitOrder(user, to, amountOffer, amountRemain, price, LIMIT_BUY);
            //产生订单创建事件
            emit OrderCreated(user, to, amountOffer, amountRemain, price, LIMIT_BUY);
        }
        //如果完全成交则在成交过程中直接产生订单创建事件和订单成交事件,链上不保存订单历史数据

        //更新余额
        quoteBalance = amountRemain != amountOffer ? IERC20(quoteToken).balanceOf(address(this)) : balance;
    }

    //创建限价卖订单
    function createSellLimitOrder(
        address user,
        uint price,
        address to)
    external
    lock
    returns (uint orderId) {
        require(price > 0 && price % priceStep == 0, 'UniswapV2 OrderBook: Price Invalid');

        //需要将token转移到order book合约, 以免与pair中的token混合
        uint balance = IERC20(baseToken).balanceOf(address(this));
        uint amountOffer = balance > baseBalance ? balance - baseBalance : 0;
        require(amountOffer >= minAmount, 'UniswapV2 OrderBook: Amount Invalid');

        //先在流动性池将价格拉到挂单价，同时还需要吃掉价格范围内的反方向挂单
        uint amountRemain = _movePriceDown(amountOffer, price, to);
        if (amountRemain != 0) {
            //未成交的部分生成限价买单
            orderId = _addLimitOrder(user, to, amountOffer, amountRemain, price, LIMIT_SELL);
            //产生订单创建事件
            emit OrderCreated(user, to, amountOffer, amountRemain, price, LIMIT_SELL);
        }

        //更新余额
        baseBalance = amountRemain != amountOffer ? IERC20(baseToken).balanceOf(address(this)) : balance;
    }

    function cancelLimitOrder(uint orderId) external lock {
        Order memory o = marketOrders[orderId];
        require(o.owner == msg.sender);

        _removeLimitOrder(o);

        address token = o.orderType == 1 ? quoteToken : baseToken;
        _singleTransfer(token, o.to, o.amountRemain);

        //更新token余额
        uint balance = IERC20(token).balanceOf(address(this));
        if (o.orderType == 1) quoteBalance = balance;
        else baseBalance = balance;

        emit OrderCanceled(o.owner, o.to, o.amountOffer, o.amountRemain, o.price, o.orderType);
    }

    //由pair的swap接口调用
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
        while(index < length && amountLeft > 0){
            uint orderId = pop(direction, price);
            Order memory order = marketOrders[orderId];
            require(orderId == order.orderId && order.orderType == 1 && price == order.price,
                'UniswapV2 OrderBook: Order Invalid');
            accounts[index] = order.to;
            amounts[index] = amountLeft > order.amountRemain ? order.amountRemain : amountLeft;
            order.amountRemain = order.amountRemain - amounts[index];
            //触发订单交易事件
            emit OrderClosed(order.owner, order.to, order.price, order.amountOffer, order
                .amountRemain, order.orderType);

            //如果还有剩余，将剩余部分入队列，交易结束
            if (order.amountRemain != 0) {
                push(direction, price, order.orderId);
                break;
            }

            //删除订单
            delete marketOrders[orderId];

            //删除用户订单
            uint userOrderSize = userOrders[order.owner].length;
            require(userOrderSize > order.orderIndex);
            //直接用最后一个元素覆盖当前元素
            userOrders[order.owner][order.orderIndex] = userOrders[order.owner][userOrderSize - 1];
            //删除最后元素
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
        uint orderDir = ~tradeDir; // 订单方向与交易方向相反
        amountInLeft = amountInOffer;
        amountOutGet = 0;
        (uint price, uint amount) = nextBook(orderDir, 0);
        while (price != 0) {
            uint amountInUsed;
            uint amountOutUsed;
            //先计算pair从当前价格到price消耗amountIn的数量
            (amountInUsed, amountOutUsed, reserveInRet, reserveOutRet) = OrderBookLibrary.getAmountForMovePrice(
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
        uint tradeDir = ~tradeDirection(tokenOut);
        uint orderDir = ~tradeDir; // 订单方向与交易方向相反
        amountOutLeft = amountOutOffer;
        amountInGet = 0;
        (uint price, uint amount) = nextBook(orderDir, 0);
        while (price != 0) {
            uint amountInUsed;
            uint amountOutUsed;
            //先计算pair从当前价格到price消耗amountIn的数量
            (amountInUsed, amountOutUsed, reserveInRet, reserveOutRet) = OrderBookLibrary.getAmountForMovePrice(
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
        (uint reserveIn, uint reserveOut) = OrderBookLibrary.getReserves(pair, tokenIn,
            tokenIn == baseToken ? quoteToken: baseToken);
        require(msg.sender == pair, "UniswapV2 OrderBook: FORBIDDEN");

        //direction for tokenA swap to tokenB
        uint direction = tradeDirection(tokenIn);
        uint amountInLeft = amountIn;

        (uint price, uint amount) = nextBook(~direction, 0); // 订单方向与交易方向相反
        //只处理挂单，reserveIn/reserveOut只用来计算需要消耗的挂单数量和价格范围
        while (price != 0) {
            //先计算pair从当前价格到price消耗amountIn的数量
            {
                uint amountInUsed;
                uint amountOutUsed;
                (amountInUsed, amountOutUsed, reserveIn, reserveOut) =
                OrderBookLibrary.getAmountForMovePrice(
                    direction,
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
                    getAmountAndTakePrice(to, ~direction, amountInLeft, price, priceDecimal, amount);
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

            (price, amount) = nextBook(~direction, price);
        }

        if (amountInLeft > 0) {
            amountAmmOut +=  OrderBookLibrary.getAmountOut(amountInLeft, reserveIn, reserveOut);
        }
    }
}
