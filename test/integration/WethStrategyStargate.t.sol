// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../TestHelpers.sol";
import "solmate/tokens/ERC20.sol";
import "src/Vault.sol";
import "src/strategies/WethStrategyStargate.sol";
import "src/Swap.sol";
import "src/zaps/WethZap.sol";

contract WethStrategyStargateTest is TestHelpers {
    Vault vault;
    WethZap zap;
    WethStrategyStargate strategy;
    Swap swap;

    address constant u1 = address(0xABCD);
    address constant treasury = address(0xAAAF);

    ERC20 constant WETH9 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // 0.001 WETH
    uint256 internal constant lowerLimit = 1e15;
    // 1000 WETH
    uint256 internal constant upperLimit = 1000e18;

    ERC20 constant STG = ERC20(0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6);

    function setUp() public {
        vault = new Vault(WETH9, 0, 0, address(0), address(this), new address[](0));
        swap = new Swap();
        zap = new WethZap(vault);

        strategy = new WethStrategyStargate(vault, treasury, address(0), address(this), new address[](0), swap);
        vault.addStrategy(strategy, 100);
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

    // to receive ETH refund from redeemLocal
    receive() external payable {}

    /*/////////////////
    /      Tests      /
    /////////////////*/

    function testDepositAndInvest(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositWeth(u1, amount, u1);

        assertEq(vault.totalAssets(), amount);

        vault.report(strategy);
        assertVeryCloseTo(strategy.totalAssets(), amount, 1); // 0.001%
    }

    function testWithdraw(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositWeth(u1, amount, u1);

        vault.report(strategy);

        vm.startPrank(u1);
        vault.redeem(vault.balanceOf(u1), u1, u1);

        assertVeryCloseTo(WETH9.balanceOf(u1), amount, 1); // 0.001%
    }

    function testHarvest(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositWeth(u1, amount, u1);

        vault.report(strategy);

        uint256 startingAssets = strategy.totalAssets();

        assertEq(STG.balanceOf(treasury), 0);

        vm.roll(block.number + 10_000);

        vault.harvest(strategy);

        assertGe(strategy.totalAssets(), startingAssets);
        assertGt(WETH9.balanceOf(treasury), 0);
    }

    function testManualWithdraw(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositWeth(u1, amount, u1);

        vault.report(strategy);

        strategy.manualWithdraw{value: 1e18}(
            110,
            amount,
            IStargateRouter.lzTxObj({dstGasForCall: 0, dstNativeAmount: 0, dstNativeAddr: abi.encodePacked(address(0))})
        );
    }
}
