pragma solidity =0.5.16;

import "../OrderBook.sol";

contract OrderBookTest is OrderBook {
    function getAmountForMovePrice(uint reserveIn, uint reserveOut, uint price, uint decimal)
    external pure returns (uint amountIn, uint amountOut, uint reserveInNew, uint reserveOutNew){
        (amountIn, amountOut, reserveInNew, reserveOutNew) =
            OrderBookLibrary.getAmountForMovePrice(reserveIn, reserveOut, price, decimal);
    }
}