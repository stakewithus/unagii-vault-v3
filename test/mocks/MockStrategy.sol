// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";

import "src/Strategy.sol";
import "./MockERC20.sol";

contract MockStrategy is Strategy {
    using SafeTransferLib for ERC20;

    // to simulate slippage and bonuses
    uint256 slippageOnNextInvest;
    uint256 slippageOnNextWithdraw;
    uint256 bonusOnNextWithdraw;

    constructor(Vault _vault) Strategy(_vault, address(0), address(0), address(this), new address[](0)) {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function setSlippageOnNextInvest(uint256 _slippage) external {
        slippageOnNextInvest = _slippage;
    }

    function setSlippageOnNextWithdraw(uint256 _slippage) external {
        slippageOnNextWithdraw = _slippage;
    }

    function setBonusOnNextWithdraw(uint256 _bonus) external {
        bonusOnNextWithdraw = _bonus;
    }

    function _withdraw(uint256 _assets) internal override returns (uint256 received) {
        uint256 amount = _assets;

        if (slippageOnNextWithdraw > 0) {
            amount -= slippageOnNextWithdraw;

            MockERC20 mockAsset = MockERC20(address(asset));
            mockAsset.burn(address(this), slippageOnNextWithdraw);

            slippageOnNextWithdraw = 0;
        }

        if (bonusOnNextWithdraw > 0) {
            amount += bonusOnNextWithdraw;

            MockERC20 mockAsset = MockERC20(address(asset));
            mockAsset.mint(address(this), bonusOnNextWithdraw);

            bonusOnNextWithdraw = 0;
        }

        asset.safeTransfer(address(vault), amount);
        return amount;
    }

    function _harvest() internal override {}

    function _invest() internal override {
        if (slippageOnNextInvest == 0) return;

        // burn during _invest to simulate slippage
        MockERC20 mockAsset = MockERC20(address(asset));
        mockAsset.burn(address(this), slippageOnNextInvest);

        slippageOnNextInvest = 0;
    }
}
