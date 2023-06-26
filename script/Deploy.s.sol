// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "src/strategies/UsdcStrategyStargate.sol";
import "src/strategies/WethStrategyConvexStEth.sol";
import "src/zaps/WethZap.sol";

contract Deploy is Script {
    Swap swap = Swap(vm.envAddress("SWAP_ADDRESS"));
    address treasury = vm.envAddress("TREASURY_ADDRESS");
    address multisig = vm.envAddress("MULTISIG_ADDRESS");
    address timeLock = vm.envAddress("TIMELOCK_ADDRESS");
    address[] authorized = vm.envAddress("AUTH_ADDRESSES", ",");

    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 constant WETH9 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    uint8 constant delay = 5;
    uint256 constant float = 5;

    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        Vault usdcVault = new Vault(USDC, delay, float, timeLock, multisig, authorized);

        UsdcStrategyStargate usdcStrategy = new UsdcStrategyStargate(
    usdcVault,
    treasury,
    timeLock,
    multisig,
    authorized,
    swap
    );
        usdcVault.addStrategy(usdcStrategy, 95);

        Vault wethVault = new Vault(WETH9, delay, float, timeLock, multisig, authorized);

        WethStrategyConvexStEth wethStrategy = new WethStrategyConvexStEth(
    wethVault,
    treasury,
    timeLock,
    multisig,
    authorized,
    swap
    );

        wethVault.addStrategy(wethStrategy, 95);
        new WethZap(wethVault);

        vm.stopBroadcast();
    }
}
