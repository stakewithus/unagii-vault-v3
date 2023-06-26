//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

// https://curve.readthedocs.io/exchange-pools.html#metapools
// for pre-factory curve metapools. main differences are one zap per pool and lpToken is separate ERC20

interface IGen2MetaPool {
    function exchange(int128, int128, uint256, uint256) external returns (uint256);

    function base_virtual_price() external view returns (uint256);
}
