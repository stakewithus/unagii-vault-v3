// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "forge-std/Test.sol";
import "src/Swap.sol";

contract SwapTest is Test {
    address internal constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function testDeploysCorrectly() public {
        Swap swap = new Swap();
        Swap.RouteInfo memory info = swap.getRoute(CVX, WETH);
        assert(info.route == Swap.Route.UniswapV3Direct);
    }
}
