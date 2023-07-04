// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "solmate/tokens/WETH.sol";
import "src/Vault.sol";
import "src/zaps/WethZap.sol";

uint8 constant BLOCK_DELAY = 10;

contract WethZapTest is Test {
    WETH weth;
    Vault vault;
    WethZap zap;

    address constant u1 = address(0xAAA1);
    address constant u2 = address(0xAAA2);
    address constant u3 = address(0xAAA3);

    function setUp() public {
        weth = new WETH();
        vault = new Vault({
            _asset: weth,
            _blockDelay: BLOCK_DELAY,
            _floatDebtRatio: 0,
            _nominatedOwner: address(0),
            _admin: address(this),
            _authorized: new address[](0)
        });
        zap = new WethZap(vault);

        vm.roll(100);
    }

    function testSafeDeposit() public {
        uint256 shares = 0;
        deal(u1, 1000);

        // user 1 deposit
        vm.prank(u1);
        shares = zap.safeDepositETH{value: 100}(u1, 1);
        assertGt(shares, 0);
        assertEq(vault.balanceOf(u1), shares);

        // user 1 deposits for user 2
        vm.prank(u1);
        shares = zap.safeDepositETH{value: 100}(u2, 1);
        assertGt(shares, 0);
        assertEq(vault.balanceOf(u2), shares);

        // Cannot deposit when paused
        zap.pause();
        vm.expectRevert(WethZap.Paused.selector);
        vm.prank(u1);
        zap.safeDepositETH{value: 100}(u1, 1);
    }

    function testSafeRedeem() public {
        deal(u1, 1000);

        // Deposit
        vm.prank(u1);
        uint256 shares = zap.safeDepositETH{value: 1000}(u1, 1);
        vm.roll(block.number + BLOCK_DELAY);

        // Approve
        vm.prank(u1);
        vault.approve(address(zap), type(uint256).max);

        // Cannot withdraw if paused
        zap.pause();
        vm.expectRevert(WethZap.Paused.selector);
        vm.prank(u1);
        zap.safeRedeemETH(shares, shares);
        zap.unpause();

        // Withdraw
        uint256 balBefore = u1.balance;
        vm.prank(u1);
        zap.safeRedeemETH(shares, shares);
        uint256 balAfter = u1.balance;

        assertEq(balAfter - balBefore, 1000);
    }

    function testPauseAndUnpause() public {
        // Not authorized
        vm.expectRevert(Ownership.Unauthorized.selector);
        vm.prank(u3);
        zap.pause();

        vm.expectRevert(Ownership.Unauthorized.selector);
        vm.prank(u3);
        zap.unpause();

        // Owner
        zap.pause();
        assertTrue(zap.paused());

        zap.unpause();
        assertTrue(!zap.paused());
    }
}
