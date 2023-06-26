// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

// https://curve.readthedocs.io/factory-deposits.html
// deposit zap for curve factory metapools

interface IFactoryDepositZap {
    function add_liquidity(address _pool, uint256[4] memory _deposit_amounts, uint256 min_mint_amount)
        external
        returns (uint256);

    function remove_liquidity_one_coin(
        address _pool,
        uint256 _burn_amount,
        int128 _i,
        uint256 _min_amount,
        address _receiver
    ) external returns (uint256);
}
