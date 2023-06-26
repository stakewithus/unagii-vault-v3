// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "solmate/utils/FixedPointMathLib.sol";
import "forge-std/Test.sol";
import "src/Staking.sol";
import "test/mocks/MockERC20.sol";

contract StakingTest is Test {
    using FixedPointMathLib for uint256;

    MockERC20 asset;
    MockERC20 reward;

    Staking staking;

    address u1 = address(0xAAA1);
    address u2 = address(0xAAA2);
    address u3 = address(0xAAA3);

    function setUp() public {
        asset = new MockERC20('Mock Asset', 'mAsset', 18);
        reward = new MockERC20('Mock Reward', 'mReward', 18);
        staking = new Staking(asset, reward, address(0), address(this), new address[](0));
    }

    function deposit(address from, uint256 amount) internal {
        asset.mint(from, amount);

        vm.startPrank(from);
        asset.approve(address(staking), amount);
        staking.deposit(amount);
        vm.stopPrank();
    }

    function testDepositAndWithdraw(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);

        assertEq(staking.totalShares(), 0);
        assertEq(staking.shares(u1), 0);
        assertEq(staking.lockedAssets(u1), 0);

        deposit(u1, amount);

        assertEq(staking.shares(u1), amount);
        assertEq(staking.totalShares(), amount);
        assertEq(staking.lockedAssets(u1), amount);
        assertEq(staking.freeAssets(u1), 0);

        vm.warp(block.timestamp + 7 days);

        assertEq(staking.lockedAssets(u1), 0);
        assertEq(staking.freeAssets(u1), amount);

        vm.prank(u1);
        staking.withdraw(amount);

        assertEq(staking.shares(u1), 0);
        assertEq(staking.totalShares(), 0);
        assertEq(asset.balanceOf(u1), amount);
    }

    function testRewardDistribution() public {
        staking.setLockDuration(0);

        deposit(u1, 200);
        deposit(u2, 100);

        reward.mint(address(staking), 3);

        assertEq(staking.currentRewardBalance(), 0);

        staking.updateTotalRewards();

        deposit(u3, 100); // u3 deposited after update, so he shouldn't have a share of rewards

        assertEq(staking.currentRewardBalance(), 3);
        assertEq(staking.totalRewardsPerShare(), uint256(3).mulDivDown(1e18, 300));
        assertEq(staking.unclaimedRewards(u1), 2);
        assertEq(staking.unclaimedRewards(u2), 1);
        assertEq(staking.unclaimedRewards(u3), 0);

        reward.mint(address(staking), 4);
        staking.updateTotalRewards();

        assertEq(staking.currentRewardBalance(), 7);
        assertEq(staking.unclaimedRewards(u1), 4);
        assertEq(staking.unclaimedRewards(u2), 2);
        assertEq(staking.unclaimedRewards(u3), 1);

        vm.startPrank(u1);
        staking.claimRewards();
        staking.withdraw(100);
        vm.stopPrank();

        assertEq(staking.currentRewardBalance(), 3);
        assertEq(reward.balanceOf(u1), 4);
        assertEq(staking.unclaimedRewards(u1), 0);

        deposit(u2, 300);

        // u1: 100, u2: 400, u3: 100
        reward.mint(address(staking), 6);
        staking.updateTotalRewards();

        assertEq(staking.currentRewardBalance(), 9);
        assertEq(staking.unclaimedRewards(u1), 1);
        assertEq(staking.unclaimedRewards(u2), 6);
        assertEq(staking.unclaimedRewards(u3), 2);
    }
}
