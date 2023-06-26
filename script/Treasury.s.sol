// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;

import "forge-std/console.sol";
import "forge-std/Script.sol";

import "src/Staking.sol";
import "src/treasury/TreasuryConvexTricrypto.sol";

contract Deploy is Script {
    Swap swap = Swap(vm.envAddress("SWAP_ADDRESS"));

    address wethVault = vm.envAddress("WETH_VAULT");
    address usdcVault = vm.envAddress("USDC_VAULT");
    address multisig = vm.envAddress("MULTISIG_ADDRESS");
    address timeLock = vm.envAddress("TIMELOCK_ADDRESS");
    address[] authorized = vm.envAddress("AUTH_ADDRESSES", ",");

    ERC20 constant WETH9 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function run() external broadcast {
        Staking wethStaking = new Staking(ERC20(wethVault), WETH9, timeLock, multisig, authorized);

        TreasuryConvexTricrypto wethTreasury = new TreasuryConvexTricrypto(
    wethStaking,
    timeLock,
    multisig,
    authorized,
    swap,
    2
    );

        wethStaking.addAuthorized(address(wethTreasury));

        Staking usdcStaking = new Staking(ERC20(usdcVault), USDC, timeLock, multisig, authorized);

        TreasuryConvexTricrypto usdcTreasury = new TreasuryConvexTricrypto(
    usdcStaking,
    timeLock,
    multisig,
    authorized,
    swap,
    0
    );

        usdcStaking.addAuthorized(address(usdcTreasury));
    }

    modifier broadcast() {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        _;
        vm.stopBroadcast();
    }
}
