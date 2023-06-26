// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// https://etherscan.io/address/0xd51a44d3fae010294c616388b506acda1bfaae46

interface ITricryptoPool {
    function add_liquidity(uint256[3] memory _amounts, uint256 min_mint_amount) external;

    function remove_liquidity_one_coin(uint256 _token_amount, uint256 _i, uint256 _min_amount) external;

    function coins(uint256 _i) external returns (address);
}
