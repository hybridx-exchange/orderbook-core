pragma solidity =0.5.16;

import './interfaces/IUniswapV2Factory.sol';
import './OrderBook.sol';

contract OrderBookFactory is IOrderBookFactory {

    mapping(address => mapping(address => address)) public getOrderBook;
    address[] public allOrderBooks;
    address public pairFactory;
    address public WETH;

    event OrderBookCreated(
        address pair,
        address indexed baseToken,
        address indexed quoteToken,
        address orderBook,
        uint,
        uint);

    constructor(address _factory, address _WETH) public {
        pairFactory = _factory;
        WETH = _WETH;
    }

    function allOrderBookLength() external view returns (uint) {
        return allOrderBooks.length;
    }

    //create order book
    function createOrderBook(address baseToken, address quoteToken, uint priceStep, uint minAmount) external {
        require(baseToken != quoteToken, 'OF: IDENTICAL_ADDRESSES');
        (address token0, address token1) = baseToken < quoteToken ? (baseToken, quoteToken) : (quoteToken, baseToken);
        require(token0 != address(0), 'OF: ZERO_ADDRESS');
        require(getOrderBook[token0][token1] == address(0), 'OF: ORDER_BOOK_EXISTS');

        address pair = IUniswapV2Factory(pairFactory).getPair(token0, token1);
        require(pair != address(0), 'OF: TOKEN_PAIR_NOT_EXISTS');
        bytes memory bytecode = type(OrderBook).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        address orderBook;
        assembly {
            orderBook := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IOrderBook(orderBook).initialize(pair, baseToken, quoteToken, priceStep, minAmount);
        getOrderBook[token0][token1] = orderBook;
        getOrderBook[token1][token0] = orderBook;
        allOrderBooks.push(orderBook);
        emit OrderBookCreated(pair, baseToken, quoteToken, orderBook, priceStep, minAmount);
    }

    function getCodeHash() external pure returns (bytes32) {
        return keccak256(type(OrderBook).creationCode);
    }
}
