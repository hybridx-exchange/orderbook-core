pragma solidity >=0.5.0;

interface IOrderBook {
    //order book contract init function
    function initialize(
        address pair,
        address baseToken,
        address quoteToken,
        uint priceStep,
        uint minAmount)
    external;

    //create limit buy order
    function createBuyLimitOrder(
        address user,
        uint price,
        address to)
    external
    returns (uint orderId);

    //create limit sell order
    function createSellLimitOrder(
        address user,
        uint price,
        address to)
    external
    returns (uint orderId);

    //cancel limit order
    function cancelLimitOrder(uint orderId) external;

    //return user order by order index
    function userOrders(address user, uint index) external view returns (uint orderId);

    //return user all order ids
    function getUserOrders(address user) external view returns (uint[] memory orderIds);

    //return order details by order id
    function marketOrder(uint orderId) external view returns (uint[] memory order);

    //return market order book information([price...], [amount...])
    function marketBook(
        uint direction,
        uint32 maxSize)
    external
    view
    returns (uint[] memory prices, uint[] memory amounts);

    //order book within price range
    function rangeBook(uint direction, uint price)
    external
    view
    returns (uint[] memory prices, uint[] memory amounts);

    //get lp price
    function getPrice()
    external
    view
    returns (uint price);

    //get pair address
    function pair() external view returns (address);

    //get base token decimal
    function baseDecimal() external view returns (uint);
    //get price decimal
    function priceDecimal() external view returns (uint);
    //get protocol fee rate
    function protocolFeeRate() external view returns (uint);
    //get subsidy fee rate
    function subsidyFeeRate() external view returns (uint);

    //base token -- eg: btc
    function baseToken() external view returns (address);
    //quote token -- eg: usdc
    function quoteToken() external view returns (address);
    //get price step
    function priceStep() external view returns (uint);
    //update price step
    function priceStepUpdate(uint newPriceStep) external;
    //min amount
    function minAmount() external view returns (uint);
    //update min amount
    function minAmountUpdate(uint newMinAmount) external;
    //update protocol fee rate
    function protocolFeeRateUpdate(uint newProtocolFeeRate) external;
    //update subsidy fee rate
    function subsidyFeeRateUpdate(uint newSubsidyFeeRate) external;
    //get amount out for move price, include swap and take, and call by uniswap v2 pair
    function getAmountOutForMovePrice(address tokenIn, uint amountInOffer)
    external
    view
    returns (uint amountOut);

    //get amount in for move price, include swap and take, and call by uniswap v2 pair
    function getAmountInForMovePrice(address tokenOut, uint amountOutOffer)
    external
    view
    returns (uint amountIn);

    //take order when move price by uniswap v2 pair
    function takeOrderWhenMovePrice(address tokenIn, uint amountIn, address to)
    external
    returns (uint amountOut, address[] memory accounts, uint[] memory amounts);
}
