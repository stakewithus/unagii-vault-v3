// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "test/TestHelpers.sol";
import "src/Vault.sol";
import "src/Strategy.sol";
import "src/Swap.sol";
import "src/zaps/WethZap.sol";

abstract contract WethStrategyTest is TestHelpers {
    Vault vault;
    WethZap zap;
    Strategy strategy;
    Swap swap;

    address constant u1 = address(0xABCDEF);
    address constant treasury = address(0xAAAAAF);
    ERC20 constant WETH9 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // 0.001 WETH
    uint256 internal constant lowerLimit = 1e15;
    // 1000 WETH
    uint256 internal constant upperLimit = 1e21;

    function setUp() public virtual {
        vault = new Vault(WETH9, 0, 0, address(0), address(this), new address[](0));
        swap = new Swap();
        zap = new WethZap(vault);

        // override, super.setUp(), deploy strategy, then add strategy to vault
    }

    /*///////////////////
    /      Helpers      /
    ///////////////////*/

    function depositWeth(address from, uint256 amount, address receiver) public {
        vm.deal(from, amount);
        vm.startPrank(from);
        zap.depositETH{value: amount}(receiver);
        vm.stopPrank();
    }

    /*/////////////////
    /      Tests      /
    /////////////////*/

    function testDepositAndInvest(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositWeth(u1, amount, u1);

        assertEq(vault.totalAssets(), amount);

        vault.report(strategy);
        assertCloseTo(strategy.totalAssets(), amount, 10); // 1%
    }

    function testWithdraw(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositWeth(u1, amount, u1);

        vault.report(strategy);

        vm.startPrank(u1);
        vault.approve(address(zap), type(uint256).max);
        zap.redeemETH(vault.balanceOf(u1));

        assertCloseTo(address(u1).balance, amount, 10); // 1%
    }

    function testHarvest(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositWeth(u1, amount, u1);

        vault.report(strategy);

        uint256 startingAssets = strategy.totalAssets();

        assertEq(WETH9.balanceOf(treasury), 0);

        vm.warp(block.timestamp + 14 days);
        vm.roll(block.number + 5);

        vault.harvest(strategy);

        assertGt(strategy.totalAssets(), startingAssets);
        assertGt(WETH9.balanceOf(treasury), 0);
    }
}
