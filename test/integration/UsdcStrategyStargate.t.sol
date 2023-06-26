// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../TestHelpers.sol";
import "solmate/tokens/ERC20.sol";
import "src/Vault.sol";
import "src/strategies/UsdcStrategyStargate.sol";
import "src/Swap.sol";

contract UsdcStrategyStargateTest is TestHelpers {
    Vault vault;
    Swap swap;
    StrategyStargate strategy;

    address constant u1 = address(0xABCD);
    address constant treasury = address(0xAAAF);

    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant usdcWhale = 0x55FE002aefF02F77364de339a1292923A15844B8;

    uint256 internal constant lowerLimit = 1e6; // 1 USDC
    uint256 internal constant upperLimit = 1e12; // 1 million USDC

    ERC20 constant STG = ERC20(0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6);

    function setUp() public {
        vault = new Vault(USDC, 0, 0, address(0), address(this), new address[](0));
        swap = new Swap();

        strategy = new UsdcStrategyStargate(vault, treasury, address(0), address(this), new address[](0), swap);
        vault.addStrategy(strategy, 100);
    }

    /*///////////////////
    /      Helpers      /
    ///////////////////*/

    function depositUsdc(address from, uint256 amount, address receiver) public {
        vm.prank(usdcWhale);
        USDC.transfer(from, amount);
        vm.startPrank(from);
        USDC.approve(address(vault), type(uint256).max);
        vault.deposit(amount, receiver);
        vm.stopPrank();
    }

    // to receive ETH refund from redeemLocal
    receive() external payable {}

    /*/////////////////
    /      Tests      /
    /////////////////*/

    function testDepositAndInvest(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositUsdc(u1, amount, u1);

        assertEq(vault.totalAssets(), amount);

        vault.report(strategy);
        assertVeryCloseTo(strategy.totalAssets(), amount, 1); // 0.001%
    }

    function testWithdraw(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositUsdc(u1, amount, u1);

        vault.report(strategy);

        vm.startPrank(u1);
        vault.redeem(vault.balanceOf(u1), u1, u1);

        assertVeryCloseTo(USDC.balanceOf(u1), amount, 1); // 0.001%
    }

    function testHarvest(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositUsdc(u1, amount, u1);

        vault.report(strategy);

        uint256 startingAssets = strategy.totalAssets();

        assertEq(STG.balanceOf(treasury), 0);

        vm.roll(block.number + 300_000);

        vault.harvest(strategy);

        assertGe(strategy.totalAssets(), startingAssets);
        assertGt(USDC.balanceOf(treasury), 0);
    }

    function testManualWithdraw(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositUsdc(u1, amount, u1);

        vault.report(strategy);

        strategy.manualWithdraw{value: 1e18}(
            110,
            amount,
            IStargateRouter.lzTxObj({dstGasForCall: 0, dstNativeAmount: 0, dstNativeAddr: abi.encodePacked(address(0))})
        );
    }
}
