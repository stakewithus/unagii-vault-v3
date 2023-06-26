// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;

import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "src/Staking.sol";
import "src/libraries/Ownership.sol";

abstract contract Treasury is Ownership {
    using SafeTransferLib for ERC20;

    /// @notice asset of the underlying vault
    ERC20 public immutable asset;
    /// @notice staking contract where where rewards are sent to
    Staking public immutable staking;

    constructor(Staking _staking, address _nominatedOwner, address _admin, address[] memory _authorized)
        Ownership(_nominatedOwner, _admin, _authorized)
    {
        staking = _staking;
        // the assumption here is that the asset of the underlying vault is the reward for the staking contract
        asset = staking.reward();
    }

    /*///////////////////////////
    /      Owner Functions      /
    ///////////////////////////*/

    function withdraw(ERC20 _token, address _receiver, uint256 _amount) external onlyOwner {
        _withdraw(_token, _receiver, _amount);
    }

    /*////////////////////////////////
    /      Authorized Functions      /
    ////////////////////////////////*/

    function harvest() external onlyAuthorized {
        _harvest();
        staking.updateTotalRewards();
    }

    function invest(uint256 _min) external onlyAuthorized {
        _invest(_min);
    }

    /*//////////////////////////////
    /      Internal Functions      /
    //////////////////////////////*/

    function _withdraw(ERC20 _token, address _receiver, uint256 _amount) internal {
        _token.safeTransfer(_receiver, _amount);
    }

    /*////////////////////////////
    /      Internal Virtual      /
    ////////////////////////////*/

    /// @dev this must 1. collect yield, 2. convert into reward token and 3. send reward to staking contract
    function _harvest() internal virtual;

    function _invest(uint256 _min) internal virtual;
}
