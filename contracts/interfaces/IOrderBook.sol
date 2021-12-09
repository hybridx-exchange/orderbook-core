pragma solidity >=0.5.0;

interface IOrderBook {
    //orderbook合约初始化函数
    function initialize(
        address pair,
        address baseToken,
        address quoteToken,
        uint priceStep,
        uint minAmount)
    external;

    //创建限价买订单
    function createBuyLimitOrder(
        address user,
        uint price,
        address to)
    external
    returns (uint orderId);

    //创建限价买订单
    function createSellLimitOrder(
        address user,
        uint price,
        address to)
    external
    returns (uint orderId);

    //取消订单
    function cancelLimitOrder(uint orderId) external;

    //用户订单
    function userOrders(address user, uint index) external view returns (uint orderId);

    //用户订单
    function getUserOrders(address user) external view returns (uint[] memory orderIds);

    //市场订单
    function marketOrder(uint orderId) external view returns (uint[] memory order);

    //市场订单薄
    function marketBook(
        uint direction,
        uint32 maxSize)
    external
    view
    returns (uint[] memory prices, uint[] memory amounts);

    //某个价格范围内的订单薄
    function rangeBook(uint direction, uint price)
    external
    view
    returns (uint[] memory prices, uint[] memory amounts);

    function getPrice()
    external
    view
    returns (uint price);

    function pair() external view returns (address);

    //价格小数点位数
    function priceDecimal() external view returns (uint);

    //基准token -- 比如btc
    function baseToken() external view returns (address);
    //计价token -- 比如usd
    function quoteToken() external view returns (address);
    //价格间隔
    function priceStep() external view returns (uint);
    //更新价格间隔
    function priceStepUpdate(uint newPriceStep) external;
    //最小数量
    function minAmount() external view returns (uint);
    //更新最小数量
    function minAmountUpdate(uint newMinAmount) external;

    function getAmountOutForMovePrice(address tokenIn, uint amountInOffer, uint reserveIn, uint reserveOut)
    external
    view
    returns (uint amountOutGet, uint amountInLeft, uint reserveInRet, uint reserveOutRet);

    function getAmountInForMovePrice(address tokenOut, uint amountOutOffer, uint reserveIn, uint reserveOut)
    external
    view
    returns (uint amountInGet, uint amountOutLeft, uint reserveInRet, uint reserveOutRet);

    function takeOrderWhenMovePrice(address tokenIn, uint amountIn, address to)
    external
    returns (uint amountOutLeft, address[] memory accounts, uint[] memory amounts);
}
