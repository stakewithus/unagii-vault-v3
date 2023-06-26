// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "forge-std/Test.sol";
import "solmate/utils/FixedPointMathLib.sol";
import "src/Vault.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockStrategy.sol";

contract VaultTest is Test {
    using FixedPointMathLib for uint256;

    MockERC20 token;
    Vault vault;

    address u1 = address(0xAAA1);
    address u2 = address(0xAAA2);

    function setUp() public {
        token = new MockERC20('Mock USD', 'MUSD', 6);
        vault = new Vault(token, 0, 0, address(0), address(this), new address[](0));
    }

    /*///////////////////
    /      Helpers      /
    ///////////////////*/

    function deposit(address from, uint256 amount, address receiver) internal {
        token.mint(from, amount);
        vm.startPrank(from);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(amount, receiver);
        vm.stopPrank();
    }

    /*/////////////////
    /      Tests      /
    /////////////////*/

    function testMetadata() public {
        assertEq(vault.name(), "Unagii Mock USD Vault v3");
        assertEq(vault.symbol(), "uMUSDv3");
        assertEq(vault.decimals(), 6);
        assertEq(address(vault.asset()), address(token));
    }

    function testDepositAndWithdraw(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);

        deposit(u1, amount, u1);

        assertEq(vault.balanceOf(u1), amount);
        assertEq(token.balanceOf(address(vault)), amount);
        assertEq(vault.totalAssets(), amount);

        vm.startPrank(u1);
        vault.withdraw(amount, u2, u1);
        vm.stopPrank();

        assertEq(vault.totalSupply(), 0);
        assertEq(token.balanceOf(u2), amount);
        assertEq(vault.totalAssets(), 0);
    }

    function testCannotDepositZero() public {
        vm.expectRevert(Vault.Zero.selector);
        vault.deposit(0, u1);

        deposit(u1, 100, u1);
        // mint shares for vault, increasing share price
        token.mint(address(vault), 100);

        // revert as shares minted rounded down to 0
        vm.expectRevert(Vault.Zero.selector);
        vault.deposit(1, u1);
    }

    function testReportAll(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint248).max);

        Strategy s1 = new MockStrategy(vault);
        Strategy s2 = new MockStrategy(vault);

        vault.addStrategy(s1, 200);
        vault.addStrategy(s2, 100);

        token.mint(address(vault), amount);

        vault.reportAll();

        assertEq(s1.totalAssets(), (amount * 2) / 3);
        assertEq(s2.totalAssets(), amount / 3);
    }

    function testLockedProfit(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint240).max);

        Strategy s1 = new MockStrategy(vault);
        vault.addStrategy(s1, 100);

        token.mint(address(s1), amount);
        vault.report(s1);

        assertEq(vault.lockedProfit(), amount);
        assertEq(vault.freeAssets(), 0);
        assertEq(vault.totalAssets(), amount);

        vm.warp(block.timestamp + 12 hours);

        assertEq(vault.lockedProfit(), amount.mulDivUp(1, 2));
        assertEq(vault.freeAssets(), amount.mulDivDown(1, 2));

        vm.warp(block.timestamp + 24 hours);

        assertEq(vault.lockedProfit(), 0);
        assertEq(vault.freeAssets(), amount);
    }

    function testLockedProfitZero(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint240).max);

        Strategy s1 = new MockStrategy(vault);
        vault.addStrategy(s1, 100);

        vault.setLockedProfitDuration(0);

        token.mint(address(s1), amount);
        vault.report(s1);

        assertEq(vault.lockedProfit(), 0);
        assertEq(vault.freeAssets(), amount);
        assertEq(vault.totalAssets(), amount);
    }

    function testRemoveStrategy(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint240).max);

        Strategy s1 = new MockStrategy(vault);
        vault.addStrategy(s1, 100);

        token.mint(address(vault), amount);
        vault.report(s1);

        vault.removeStrategy(s1, false, 0);

        assertEq(vault.queue().length, 0);
        assertEq(vault.totalAssets(), amount);

        (bool added,,) = vault.strategies(s1);
        assertFalse(added);
    }

    event Report(Strategy indexed strategy, uint256 harvested, uint256 gain, uint256 loss);

    function testReportLoss() public {
        uint256 amount = 100e18;
        uint256 loss = 1e18;

        Strategy s1 = new MockStrategy(vault);
        vault.addStrategy(s1, 100);

        token.mint(address(vault), amount);
        vault.report(s1);

        token.burn(address(s1), loss);

        vm.expectEmit(true, true, true, true);
        emit Report(s1, 0, 0, loss);

        vault.report(s1);

        assertEq(vault.totalAssets(), amount - loss);
    }

    event Lend(Strategy indexed strategy, uint256 assets, uint256 slippage);

    function testLendSlippage() public {
        uint256 amount = 100e18;
        uint256 slippage = 1e18;

        MockStrategy s1 = new MockStrategy(vault);
        vault.addStrategy(s1, 100);

        s1.setSlippageOnNextInvest(slippage);

        token.mint(address(vault), amount);

        vm.expectEmit(true, true, true, true);
        emit Lend(s1, amount, slippage);

        vault.report(s1);

        assertEq(vault.totalAssets(), amount - slippage);
    }

    event Collect(Strategy indexed strategy, uint256 received, uint256 slippage, uint256 bonus);

    function testCollectSlippage() public {
        uint256 amount = 100e18;
        uint256 slippage = 1e18;

        MockStrategy s1 = new MockStrategy(vault);
        vault.addStrategy(s1, 100);
        token.mint(address(vault), amount);
        vault.report(s1);

        s1.setSlippageOnNextWithdraw(slippage);

        vm.expectEmit(true, true, true, true);
        emit Collect(s1, amount - slippage, slippage, 0);

        vault.removeStrategy(s1, false, 0);

        assertEq(vault.totalAssets(), amount - slippage);
    }

    function testCollectBonus() public {
        uint256 amount = 100e18;
        uint256 bonus = 1e18;

        MockStrategy s1 = new MockStrategy(vault);
        vault.addStrategy(s1, 100);

        deposit(u1, amount, u1);
        vault.report(s1);

        s1.setBonusOnNextWithdraw(bonus);

        vm.startPrank(u1);
        vault.withdraw(amount, u1, u1);
        vm.stopPrank();

        assertEq(token.balanceOf(u1), amount);
        assertEq(vault.totalAssets(), bonus);
    }

    function testFloat(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint240).max);

        vault.setFloatDebtRatio(5);
        MockStrategy s1 = new MockStrategy(vault);
        vault.addStrategy(s1, 95);

        assertEq(vault.totalDebtRatio(), 100);
        assertEq(vault.floatDebtRatio(), 5);

        deposit(u1, amount, u1);
        vault.report(s1);

        uint256 expectedBalance = amount.mulDivDown(95, 100);

        assertEq(token.balanceOf(address(vault)), amount - expectedBalance);
        assertEq(s1.totalAssets(), expectedBalance);

        vault.setFloatDebtRatio(0);

        vault.report(s1);

        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(s1.totalAssets(), amount);
        assertEq(vault.totalDebtRatio(), 95);
        assertEq(vault.floatDebtRatio(), 0);
    }
}
