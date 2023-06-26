// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "forge-std/console.sol";
import "forge-std/Script.sol";
import "src/Swap.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        Swap swap = new Swap();

        console.log(address(swap));

        vm.stopBroadcast();
    }
}

contract GetRoute is Script {
    using Path for bytes;

    Swap swap = Swap(vm.envAddress("SWAP_ADDRESS"));

    function run() external {
        address TOKEN_IN = vm.envAddress("TOKEN_IN");
        address TOKEN_OUT = vm.envAddress("TOKEN_OUT");

        Swap.RouteInfo memory data = swap.getRoute(TOKEN_IN, TOKEN_OUT);

        console.log(uint8(data.route));

        if (data.route == Swap.Route.UniswapV2 || data.route == Swap.Route.SushiSwap) {
            address[] memory path = abi.decode(data.info, (address[]));
            for (uint8 i = 0; i < path.length; ++i) {
                console.log(path[i]);
            }
        } else if (data.route == Swap.Route.UniswapV3Direct) {
            uint24 fee = abi.decode(data.info, (uint24));
            console.log(fee);
        } else if (data.route == Swap.Route.UniswapV3Path) {
            bytes memory path = data.info;

            // paths go [address, uint24, address, uint24, address] etc
            while (true) {
                (address token,, uint24 fee) = path.decodeFirstPool();
                console.log(token);
                console.log(fee);
                if (!path.hasMultiplePools()) break;
                path = path.skipToken();
            }

            (, address tokenOut,) = path.decodeFirstPool();
            console.log(tokenOut);
        } else if (data.route == Swap.Route.BalancerBatch) {
            (IVault.BatchSwapStep[] memory steps, IAsset[] memory assets) =
                abi.decode(data.info, (IVault.BatchSwapStep[], IAsset[]));

            console.log("Pools:");

            for (uint8 i = 0; i < steps.length; i++) {
                console.log(string(abi.encodePacked(steps[i].poolId)));
            }

            console.log("Assets:");

            for (uint8 i = 0; i < assets.length; i++) {
                console.log(address(assets[i]));
            }
        } else {
            console.log("Unsupported");
        }
    }
}

contract SetSushiSwapDirectRoute is Script {
    Swap swap = Swap(vm.envAddress("SWAP_ADDRESS"));

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address TOKEN_IN = vm.envAddress("TOKEN_IN");
        address TOKEN_OUT = vm.envAddress("TOKEN_OUT");

        address[] memory path = new address[](2);

        path[0] = TOKEN_IN;
        path[1] = TOKEN_OUT;

        swap.setRoute(TOKEN_IN, TOKEN_OUT, Swap.RouteInfo({route: Swap.Route.SushiSwap, info: abi.encodePacked(path)}));

        vm.stopBroadcast();
    }
}
