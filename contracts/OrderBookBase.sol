pragma solidity =0.5.16;

import "./interfaces/IERC20.sol";
import "./libraries/UQ112x112.sol";
import "./interfaces/IWETH.sol";
import './libraries/TransferHelper.sol';
import "./libraries/OrderBookLibrary.sol";
import "./OrderQueue.sol";
import "./PriceList.sol";

contract OrderBookBase is OrderQueue, PriceList {
    using SafeMath for uint;
    using SafeMath for uint112;
    using UQ112x112 for uint224;

    struct Order {
        address owner;
        address to;
        uint orderId;
        uint price;
        uint amountOffer;
        uint amountRemain;
        uint orderType; //1: limitBuy, 2: limitSell
        uint orderIndex; //用户订单索引，一个用户最多255
    }

    bytes4 private constant SELECTOR_TRANSFER = bytes4(keccak256(bytes('transfer(address,uint256)')));

    //名称
    string public constant name = 'Uniswap V2 OrderBook';

    //order book factory
    address public factory;

    //货币对
    address public pair;

    //价格间隔参数-保证价格间隔的设置在一个合理的范围内
    uint public priceStep;
    //最小计价货币数量
    uint public minAmount;
    //价格小数点位数
    uint public priceDecimal;

    //基础货币
    address public baseToken;
    //记价货币
    address public quoteToken;

    //基础货币余额
    uint public baseBalance;
    //计价货币余额
    uint public quoteBalance;

    //protocol fee rate (按交易量百分比收取，对应万分之x)
    uint public protocolFeeRate;

    //subsidy fee rate (从协议费用中抽取一部分用于补贴吃单方，对应protocolFeeRate * x%)
    uint public subsidyFeeRate;

    //未完成总订单，链上不保存已成交的订单(订单id -> Order)
    mapping(uint => Order) public marketOrders;

    //用户订单(用户地址 -> 订单id数组)
    mapping(address => uint[]) public userOrders;

    event OrderCreated(
        address indexed owner,
        address indexed to,
        uint amountOffer,
        uint amountRemain,
        uint price,
        uint);

    event OrderUpdate(
        address indexed owner,
        address indexed to,
        uint amountOffer,
        uint amountUsed,
        uint price,
        uint);

    event OrderClosed(
        address indexed owner,
        address indexed to,
        uint amountOffer,
        uint amountUsed,
        uint price,
        uint);

    event OrderCanceled(
        address indexed owner,
        address indexed to,
        uint amountOffer,
        uint amountRemain,
        uint price,
        uint);

    constructor() public {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(
        address _pair,
        address _baseToken,
        address _quoteToken,
        uint _priceStep,
        uint _minAmount)
    external {
        require(msg.sender == factory, 'UniswapV2 OrderBook: FORBIDDEN'); // sufficient check
        require(_priceStep >= 1, 'UniswapV2 OrderBook: Price Step Invalid');
        require(_minAmount >= 1000, 'UniswapV2 OrderBook: Min Amount Invalid');
        (address token0, address token1) = (IUniswapV2Pair(_pair).token0(), IUniswapV2Pair(_pair).token1());
        require(
            (token0 == _baseToken && token1 == _quoteToken) ||
            (token1 == _baseToken && token0 == _quoteToken),
            'UniswapV2 OrderBook: Token Pair Invalid');

        pair = _pair;
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        priceStep = _priceStep;
        priceDecimal = IERC20(_quoteToken).decimals();
        minAmount = _minAmount;
        protocolFeeRate = 10; // 10/10000
        subsidyFeeRate = 50; // protocolFeeRate * 50%
    }

    function _getBaseBalance() internal view returns (uint balance) {
        balance = IERC20(baseToken).balanceOf(address(this));
    }

    function _getQuoteBalance() internal view returns (uint balance) {
        balance = IERC20(quoteToken).balanceOf(address(this));
    }

    function _updateBalance() internal {
        baseBalance = IERC20(baseToken).balanceOf(address(this));
        quoteBalance = IERC20(quoteToken).balanceOf(address(this));
    }

    function _safeTransfer(address token, address to, uint value)
    internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR_TRANSFER, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2 OrderBook: TRANSFER_FAILED');
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

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'UniswapV2 OrderBook: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    //id生成器
    uint private orderIdGenerator;
    function _generateOrderId()
    private
    returns (uint) {
        orderIdGenerator++;
        return orderIdGenerator;
    }

    function getUserOrders(address user) external view returns (uint[] memory orderIds) {
        orderIds = userOrders[user];
    }

    function getPrice()
    public
    view
    returns (uint price) {
        (uint112 reserveBase, uint112 reserveQuote) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);
        if (reserveBase != 0) {
            uint d = reserveQuote.mul(10 ** priceDecimal);
            price = d / reserveBase;
        }
    }

    function tradeDirection(address tokenIn)
    internal
    view
    returns (uint direction) {
        direction = quoteToken == tokenIn ? LIMIT_BUY : LIMIT_SELL;
    }

    //添加order对象
    function _addLimitOrder(
        address user,
        address _to,
        uint _amountOffer,
        uint _amountRemain,
        uint _price,
        uint _type)
    internal
    returns (uint orderId) {
        uint[] memory _userOrders = userOrders[user];
        require(_userOrders.length < 0xff, 'UniswapV2 OrderBook: Order Number is exceeded');
        uint orderIndex = _userOrders.length;

        Order memory order = Order(
            user,
            _to,
            _generateOrderId(),
            _price,
            _amountOffer,
            _amountRemain,
            _type,
            orderIndex);
        userOrders[user].push(order.orderId);

        marketOrders[order.orderId] = order;
        if (length(_type, _price) == 0) {
            addPrice(_type, _price);
        }

        push(_type, _price, order.orderId);

        return order.orderId;
    }

    //删除order对象
    function _removeFrontLimitOrderOfQueue(Order memory order) internal {
        // pop order from queue of same price
        pop(order.orderType, order.price);
        // delete order from market orders
        delete marketOrders[order.orderId];

        // delete user order
        uint userOrderSize = userOrders[order.owner].length;
        require(userOrderSize > order.orderIndex, 'invalid orderIndex');
        //overwrite the current element with the last element directly
        uint lastUsedOrder = userOrders[order.owner][userOrderSize - 1];
        userOrders[order.owner][order.orderIndex] = lastUsedOrder;
        //update moved order's index
        marketOrders[lastUsedOrder].orderIndex = order.orderIndex;
        // delete the last element of user order list
        userOrders[order.owner].pop();

        //delete price
        if (length(order.orderType, order.price) == 0){
            delPrice(order.orderType, order.price);
        }
    }

    //删除order对象
    function _removeLimitOrder(Order memory order) internal {
        //删除队列订单
        del(order.orderType, order.price, order.orderId);
        //删除全局订单
        delete marketOrders[order.orderId];

        // delete user order
        uint userOrderSize = userOrders[order.owner].length;
        require(userOrderSize > order.orderIndex, 'invalid orderIndex');
        //overwrite the current element with the last element directly
        uint lastUsedOrder = userOrders[order.owner][userOrderSize - 1];
        userOrders[order.owner][order.orderIndex] = lastUsedOrder;
        //update moved order's index
        marketOrders[lastUsedOrder].orderIndex = order.orderIndex;
        // delete the last element of user order list
        userOrders[order.owner].pop();

        //删除价格
        if (length(order.orderType, order.price) == 0){
            delPrice(order.orderType, order.price);
        }
    }

    // list
    function list(
        uint direction,
        uint price)
    internal
    view
    returns (uint[] memory allData) {
        uint front = limitOrderQueueFront[direction][price];
        uint rear = limitOrderQueueRear[direction][price];
        if (front < rear){
            allData = new uint[](rear - front);
            for (uint i=front; i<rear; i++) {
                allData[i-front] = marketOrders[limitOrderQueueMap[direction][price][i]].amountRemain;
            }
        }
    }

    // listAgg
    function listAgg(
        uint direction,
        uint price)
    internal
    view
    returns (uint dataAgg) {
        uint front = limitOrderQueueFront[direction][price];
        uint rear = limitOrderQueueRear[direction][price];
        for (uint i=front; i<rear; i++){
            dataAgg += marketOrders[limitOrderQueueMap[direction][price][i]].amountRemain;
        }
    }

    // total amount
    function totalOrderAmount(uint direction)
    internal
    view
    returns (uint amount)
    {
        uint curPrice = nextPrice(direction, 0);
        while(curPrice != 0){
            amount += listAgg(direction, curPrice);
            curPrice = nextPrice(direction, curPrice);
        }
    }

    //订单薄，不关注订单具体信息，只用于查询
    function marketBook(
        uint direction,
        uint32 maxSize)
    external
    view
    returns (uint[] memory prices, uint[] memory amounts) {
        uint priceLength = priceLength(direction);
        priceLength =  priceLength > maxSize ? maxSize : priceLength;
        prices = new uint[](priceLength);
        amounts = new uint[](priceLength);
        uint curPrice = nextPrice(direction, 0);
        uint32 index = 0;
        while(curPrice != 0 && index < priceLength){
            prices[index] = curPrice;
            amounts[index] = listAgg(direction, curPrice);
            curPrice = nextPrice(direction, curPrice);
            index++;
        }
    }

    //获取某个价格内的订单薄
    function rangeBook(uint direction, uint price)
    external
    view
    returns (uint[] memory prices, uint[] memory amounts) {
        uint curPrice = nextPrice(direction, 0);
        uint priceLength;
        if (direction == LIMIT_BUY) {
            while(curPrice != 0 && curPrice >= price){
                curPrice = nextPrice(direction, curPrice);
                priceLength++;
            }
        }
        else if (direction == LIMIT_SELL) {
            while(curPrice != 0 && curPrice <= price){
                curPrice = nextPrice(direction, curPrice);
                priceLength++;
            }
        }

        if (priceLength > 0) {
            prices = new uint[](priceLength);
            amounts = new uint[](priceLength);
            curPrice = nextPrice(direction, 0);
            uint index;
            while(index < priceLength) {
                prices[index] = curPrice;
                amounts[index] = listAgg(direction, curPrice);
                curPrice = nextPrice(direction, curPrice);
                index++;
            }
        }
    }

    //市场订单
    function marketOrder(
        uint orderId
    )
    external
    view
    returns (uint[] memory order){
        order = new uint[](8);
        Order memory o = marketOrders[orderId];
        order[0] = (uint)(o.owner);
        order[1] = (uint)(o.to);
        order[2] = o.orderId;
        order[3] = o.price;
        order[4] = o.amountOffer;
        order[5] = o.amountRemain;
        order[6] = o.orderType;
        order[7] = o.orderIndex;
    }

    //用于遍历所有订单
    function nextOrder(
        uint direction,
        uint cur)
    internal
    view
    returns (uint next, uint[] memory amounts) {
        next = nextPrice(direction, cur);
        amounts = list(direction, next);
    }

    //用于遍历所有订单薄
    function nextBook(
        uint direction,
        uint cur)
    internal
    view
    returns (uint next, uint amount) {
        next = nextPrice(direction, cur);
        amount = listAgg(direction, next);
    }

    //更新价格间隔，需要考虑抢先交易的问题
    function priceStepUpdate(uint newPriceStep) external lock {
        if (msg.sender != OrderBookLibrary.getAdmin(factory)){
            require(priceLength(LIMIT_BUY) == 0 && priceLength(LIMIT_SELL) == 0,
                'Hybridx OrderBook: Order Exist');
        }
        priceStep = newPriceStep;
    }

    //更新最小数量
    function minAmountUpdate(uint newMinAmount) external lock {
        if (msg.sender != OrderBookLibrary.getAdmin(factory)){
            require(priceLength(LIMIT_BUY) == 0 && priceLength(LIMIT_SELL) == 0,
                'Hybridx OrderBook: Order Exist');
        }
        minAmount = newMinAmount;
    }

    //更新协议费率，开放修改需要考虑抢先交易问题，暂时由社区账号管理
    function protocolFeeRateUpdate(uint newProtocolFeeRate) external lock {
        require(msg.sender == OrderBookLibrary.getAdmin(factory),
            "Hybridx OrderBook: Forbidden");
        require(newProtocolFeeRate <= 30); //max fee is 0.3%, default is 0.1%
        protocolFeeRate = newProtocolFeeRate;
    }

    //更新gas补贴费率
    function subsidyFeeRateUpdate(uint newSubsidyFeeRate) external lock {
        require(msg.sender == OrderBookLibrary.getAdmin(factory),
            "Hybridx OrderBook: Forbidden");
        require(newSubsidyFeeRate <= 100); //max is 100% of protocolFeeRate
        subsidyFeeRate = newSubsidyFeeRate;
    }

    //Return funds that were transferred into the contract by mistake
    function safeRefund(address token, address to) external lock {
        require(msg.sender == OrderBookLibrary.getAdmin(factory),
            "Hybridx OrderBook: Forbidden");
        uint balance = IERC20(token).balanceOf(address(this));
        uint refundBalance = balance;
        if (token == baseToken) {
            uint orderBalance = totalOrderAmount(LIMIT_SELL);
            refundBalance = balance > orderBalance ? balance - orderBalance : 0;
        }
        else if (token == quoteToken) {
            uint orderBalance = totalOrderAmount(LIMIT_BUY);
            refundBalance = balance > orderBalance ? balance - orderBalance : 0;
        }

        require(refundBalance > 0, "Insufficient balance");
        _safeTransfer(token, to, refundBalance);
    }

    function getReserves()
    external
    view
    returns (uint112 reserveBase, uint112 reserveQuote) {
        (reserveBase, reserveQuote) = OrderBookLibrary.getReserves(pair, baseToken, quoteToken);
    }

    /*************************************************************************************************
                                         libraries function for test
    **************************************************************************************************/
    /*function getSection1(uint reserveIn, uint reserveOut, uint price, uint decimal)
    external
    pure
    returns (uint section1) {
        section1 = Math.sqrt(reserveIn.mul(reserveIn).mul(9) + reserveIn.mul(reserveOut).mul(3988000).mul
        (10**decimal).div(price));
    }*/

    /*function getAmountQuoteForPriceDown(
        uint amountIn,
        uint reserveIn,
        uint reserveOut,
        uint price,
        uint decimal)
    external
    pure
    returns (uint amountOut) {
        amountOut = OrderBookLibrary.getAmountQuoteForPriceDown(amountIn, reserveIn, reserveOut, price,
            decimal);
    }

    function getAmountBaseForPriceUp(
        uint amountOut,
        uint reserveIn,
        uint reserveOut,
        uint price,
        uint decimal)
    external
    pure
    returns (uint amountIn) {
        amountIn = OrderBookLibrary.getAmountBaseForPriceUp(amountOut, reserveIn, reserveOut, price,
            decimal);
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
    }*/

    function getAmountForMovePrice(
        uint direction,
        uint amountInOffer,
        uint reserveIn,
        uint reserveOut,
        uint price,
        uint decimal)
    external pure returns (uint amountInLeft, uint amountIn, uint amountOut, uint reserveInNew, uint reserveOutNew) {
        (amountInLeft, amountIn, amountOut, reserveInNew, reserveOutNew) =
        OrderBookLibrary.getAmountForMovePrice(direction, amountInOffer, reserveIn, reserveOut, price, decimal);
    }

    /*function getAmountForTakePrice(
        uint direction,
        uint amountInOffer,
        uint price,
        uint orderAmount)
    external
    view
    returns (uint amountIn, uint amountOutWithFee, uint fee) {
        (amountIn, amountOutWithFee, fee) = OrderBookLibrary.getAmountOutForTakePrice
            (direction, amountInOffer, price, priceDecimal, orderAmount);
    }

    function getAmountsForTakePrice(
        uint direction,
        uint amount,
        uint price)
    external
    view
    returns (address[] memory accountsTo, uint[] memory amountsTo, uint amountUsed) {
        uint amountLeft = amount;
        uint index;
        uint length = length(direction, price);
        accountsTo = new address[](length);
        amountsTo = new uint[](length);
        uint decimal = priceDecimal;
        while (index < length && amountLeft > 0) {
            uint orderId = get(direction, price, index);
            if (orderId == 0) break;
            Order memory order = marketOrders[orderId];
            require(orderId == order.orderId && order.orderType == direction && price == order.price,
                'Hybridx OrderBook: Order Invalid');
            accountsTo[index] = order.to;
            uint amountTake = amountLeft > order.amountRemain ? order.amountRemain : amountLeft;
            order.amountRemain = order.amountRemain - amountTake;
            amountsTo[index] = direction == LIMIT_SELL ?
                OrderBookLibrary.getSellAmountWithPrice(amountTake.mul(1000).div(1003), price, decimal) :
                OrderBookLibrary.getBuyAmountWithPrice(amountTake.mul(1000).div(1003), price, decimal);

            amountLeft = amountLeft - amountTake;
            if (order.amountRemain != 0) {
                break;
            }

            index++;
        }

        amountUsed = amount - amountLeft;
    }*/

    /*function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut) {
       amountOut = OrderBookLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn) {
        amountIn = OrderBookLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }*/
}
