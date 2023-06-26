// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.9;

import "../TestHelpers.sol";
import "src/Staking.sol";
import "src/treasury/TreasuryConvexTricrypto.sol";
import "src/Swap.sol";
import "test/mocks/MockERC20.sol";

contract TreasuryConvexTricryptoTest is TestHelpers {
    Staking wethStaking;
    Staking usdcStaking;
    TreasuryConvexTricrypto wethTreasury;
    TreasuryConvexTricrypto usdcTreasury;

    Swap swap;

    MockERC20 shareToken;

    ERC20 constant WETH9 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 constant USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    address constant usdcWhale = 0x55FE002aefF02F77364de339a1292923A15844B8;
    address constant wethWhale = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;

    address constant u1 = address(0xAAA1);

    uint256 internal constant usdcLowerLimit = 1e6; // 1 USDC
    uint256 internal constant usdcUpperLimit = 1e12; // 1 million USDC

    uint256 internal constant wethLowerLimit = 1e16; // 0.01 WETH
    uint256 internal constant wethUpperLimit = 1e21; // 1000 WETH

    function setUp() public {
        shareToken = new MockERC20('Mock Shares', 'mShares', 18);

        wethStaking = new Staking(shareToken, WETH9, address(0), address(this), new address[](0));
        usdcStaking = new Staking(shareToken, USDC, address(0), address(this), new address[](0));

        swap = new Swap();

        wethTreasury = new TreasuryConvexTricrypto(wethStaking, address(0), address(this), new address[](0), swap, 2);
        usdcTreasury = new TreasuryConvexTricrypto(usdcStaking, address(0), address(this), new address[](0), swap, 0);

        usdcStaking.addAuthorized(address(usdcTreasury));
        wethStaking.addAuthorized(address(wethTreasury));

        // mint some shares for u1
        shareToken.mint(u1, 100);
        vm.startPrank(u1);
        shareToken.approve(address(usdcStaking), type(uint256).max);
        shareToken.approve(address(wethStaking), type(uint256).max);
        usdcStaking.deposit(50);
        wethStaking.deposit(50);
        vm.stopPrank();
    }

    /*///////////////////
    /      Helpers      /
    ///////////////////*/

    function depositUsdc(uint256 amount) public {
        vm.prank(usdcWhale);
        USDC.transfer(address(usdcTreasury), amount);
    }

    function depositWeth(uint256 amount) public {
        vm.prank(wethWhale);
        WETH9.transfer(address(wethTreasury), amount);
    }

    /*/////////////////
    /      Tests      /
    /////////////////*/

    function testUsdcFlow(uint256 amount) public {
        vm.assume(amount >= usdcLowerLimit && amount <= usdcUpperLimit);

        assertEq(usdcTreasury.totalAssets(), 0);
        assertEq(USDT.balanceOf(u1), 0);

        depositUsdc(amount);
        usdcTreasury.invest(1);

        uint256 lpAmount = usdcTreasury.totalAssets();
        assertGt(lpAmount, 0);

        assertEq(usdcStaking.currentRewardBalance(), 0);

        vm.warp(block.timestamp + 14 days);
        usdcTreasury.harvest();

        assertGt(usdcStaking.currentRewardBalance(), 0);

        usdcTreasury.unstakeAndWithdraw(lpAmount, 0, 1, u1);
        assertGt(USDT.balanceOf(u1), 0);
    }

    function testWEthFlow(uint256 amount) public {
        vm.assume(amount >= wethLowerLimit && amount <= wethUpperLimit);

        assertEq(wethTreasury.totalAssets(), 0);
        assertEq(WETH9.balanceOf(u1), 0);

        depositWeth(amount);
        wethTreasury.invest(1);

        uint256 lpAmount = wethTreasury.totalAssets();
        assertGt(lpAmount, 0);

        assertEq(wethStaking.currentRewardBalance(), 0);

        vm.warp(block.timestamp + 14 days);
        wethTreasury.harvest();

        assertGt(wethStaking.currentRewardBalance(), 0);

        wethTreasury.unstakeAndWithdraw(lpAmount, 2, 1, u1);
        assertGt(WETH9.balanceOf(u1), 0);
    }
}
