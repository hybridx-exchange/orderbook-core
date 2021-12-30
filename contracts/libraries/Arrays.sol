pragma solidity >=0.5.0;

// a library for performing various math operations

library Arrays {
    function extendUint(uint[] memory x, uint[] memory y) internal pure returns (uint[] memory z) {
        z = new uint[](x.length + y.length);
        for (uint i=0; i<x.length; i++) {
            z[i] = x[i];
        }

        for (uint i=0; i<y.length; i++) {
            z[x.length + i] = y[i];
        }
    }

    function extendAddress(address[] memory x, address[] memory y) internal pure returns (address[] memory z) {
        z = new address[](x.length + y.length);
        for (uint i=0; i<x.length; i++) {
            z[i] = x[i];
        }

        for (uint i=0; i<y.length; i++) {
            z[x.length + i] = y[i];
        }
    }

    function subAddress(address[] memory x, uint newLen) internal pure returns (address[] memory z) {
        require(newLen <= x.length);
        if (newLen == x.length) {
            z = x;
        }
        else {
            z = new address[](newLen);
            for (uint i=0; i<newLen; i++) {
                z[i] = x[i];
            }
        }
    }
}

