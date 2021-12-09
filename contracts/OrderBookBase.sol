pragma solidity =0.5.16;

import "./interfaces/IERC20.sol";
import "./libraries/UQ112x112.sol";
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
    uint internal constant LIMIT_BUY = 1;
    uint internal constant LIMIT_SELL = 2;

    //order book factory
    address public factory;

    //货币对
    address public pair;

    //价格间隔参数-保证价格间隔的设置在一个合理的范围内
    uint public priceStep;
    //最小数量
    uint public minAmount;
    //价格小数点位数
    uint public priceDecimal;

    //基础货币
    address public baseToken;
    //记价货币
    address public quoteToken;

    uint internal baseBalance;
    uint internal quoteBalance;

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
        require(_minAmount >= 1, 'UniswapV2 OrderBook: Min Amount Invalid');
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
    }

    function _safeTransfer(address token, address to, uint value)
    internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR_TRANSFER, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2 OrderBook: TRANSFER_FAILED');
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

    function getReserves()
    internal
    view
    returns (uint112 reserveBase, uint112 reserveQuote, uint32 blockTimestampLast) {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        reserveBase = baseToken == IUniswapV2Pair(pair).token0() ? _reserve0 : _reserve1;
        reserveQuote = reserveBase == _reserve0 ? _reserve1 : _reserve0;
        blockTimestampLast = _blockTimestampLast;
    }

    function getPrice()
    external
    view
    returns (uint price){
        (uint112 reserveBase, uint112 reserveQuote,) = getReserves();
        if (reserveBase != 0){
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
            _amountOffer,
            _amountRemain,
            _price,
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
    function _removeLimitOrder(Order memory order) internal {
        //删除全局订单
        delete marketOrders[order.orderId];

        //删除用户订单
        uint[] memory _userOrders = userOrders[order.owner];
        require(_userOrders.length > order.orderIndex, 'invalid orderIndex');
        //直接用最后一个元素覆盖当前元素
        if (order.orderIndex != _userOrders.length - 1) {
            _userOrders[order.orderIndex] = _userOrders[_userOrders.length - 1];
        }

        //删除用户订单
        userOrders[order.owner].pop();

        //删除队列订单
        del(order.orderType, order.price, order.orderId);

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
    returns (uint[] memory prices, uint[] memory amounts){
        uint priceLength = priceLength(direction);
        prices = new uint[](priceLength);
        amounts = new uint[](priceLength);
        uint curPrice = nextPrice(direction, 0);
        uint32 index = 0;
        while(curPrice != 0 && curPrice <= price){
            prices[index] = curPrice;
            amounts[index] = listAgg(direction, curPrice);
            curPrice = nextPrice(direction, curPrice);
            index++;
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
}
