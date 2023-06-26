// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "forge-std/Test.sol";
import "solmate/tokens/ERC20.sol";
import "src/Vault.sol";
import "src/strategies/UsdcStrategyCompound.sol";
import "src/Swap.sol";
import "../TestHelpers.sol";

contract UsdcStrategyCompoundTest is Test, TestHelpers {
    Vault vault;
    Swap swap;
    StrategyCompound strategy;

    address constant u1 = address(0xABCD);
    address constant treasury = address(0xAAAF);

    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant usdcWhale = 0x55FE002aefF02F77364de339a1292923A15844B8;

    // 1 USDC
    uint256 internal constant lowerLimit = 1e6;
    // 10 million USDC
    uint256 internal constant upperLimit = 10e12;

    ERC20 constant COMP = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public {
        vault = new Vault(USDC, 0, 0, address(0), address(this), new address[](0));
        swap = new Swap();

        address[] memory path = new address[](3);
        path[0] = address(COMP);
        path[1] = WETH;
        path[2] = address(USDC);

        swap.setRoute(
            address(COMP), address(USDC), Swap.RouteInfo({route: Swap.Route.SushiSwap, info: abi.encode(path)})
        );

        strategy = new UsdcStrategyCompound(vault, treasury, address(0), address(this), new address[](0), swap);
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

    /*/////////////////
    /      Tests      /
    /////////////////*/

    function testDepositAndInvest(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositUsdc(u1, amount, u1);

        assertEq(vault.totalAssets(), amount);

        vault.report(strategy);

        (uint256 supplied, uint256 borrowed,, uint256 safeCol, uint256 collateralRatio) = strategy.getHealth();

        assertVeryCloseTo(supplied - borrowed, amount, 1); // 0.01%
        assertLe(collateralRatio, safeCol);
    }

    function testWithdraw(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositUsdc(u1, amount, u1);

        vault.report(strategy);

        vm.startPrank(u1);
        vault.redeem(vault.balanceOf(u1), u1, u1);

        assertCloseTo(USDC.balanceOf(u1), amount, 1); // 0.1%
    }

    function testHarvest(uint256 amount) public {
        vm.assume(amount >= lowerLimit && amount <= upperLimit);

        depositUsdc(u1, amount, u1);

        vault.report(strategy);

        uint256 startingAssets = strategy.totalAssets();

        assertEq(USDC.balanceOf(treasury), 0);

        vm.roll(block.number + 100_000);

        vault.harvest(strategy);

        (uint256 supplied, uint256 borrowed,, uint256 safeCol, uint256 collateralRatio) = strategy.getHealth();

        assertGt(supplied - borrowed, startingAssets);
        assertGt(USDC.balanceOf(treasury), 0);
        assertLe(collateralRatio, safeCol);
    }

    function testSetBufferAndRebalance() public {
        uint256 amount = upperLimit;

        depositUsdc(u1, amount, u1);

        vault.report(strategy);

        (,,, uint256 safeCol, uint256 collateralRatio) = strategy.getHealth();

        (, uint256 marketCol,) = strategy.comptroller().markets(address(strategy.cToken()));

        assertEq(safeCol, marketCol - (0.04 * 1e18));
        assertLe(collateralRatio, safeCol);

        strategy.setBufferAndRebalance(0.08 * 1e18);

        (,,, safeCol, collateralRatio) = strategy.getHealth();

        assertEq(safeCol, marketCol - (0.08 * 1e18));
        assertLe(collateralRatio, safeCol);

        // do not leverage
        strategy.setBufferAndRebalance(1e18);

        uint256 borrowed;
        (, borrowed,, safeCol, collateralRatio) = strategy.getHealth();

        assertEq(safeCol, 0);
        assertEq(collateralRatio, 0);
        assertEq(borrowed, 0);
    }
}
