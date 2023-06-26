// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

// https://curve.readthedocs.io/exchange-deposits.html#deposit-zap-api-new
// for pre-factory metapools, with one deposit zap per pool

interface IGen2DepositZap {
    function add_liquidity(uint256[4] memory _deposit_amounts, uint256 min_mint_amount) external returns (uint256);

    function remove_liquidity_one_coin(uint256 _burn_amount, int128 _i, uint256 _min_amount)
        external
        returns (uint256);

    function pool() external returns (address);
}
