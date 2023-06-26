//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

// https://etherscan.io/address/0x93054188d876f558f4a66B2EF1d97d16eDf0895B#code

interface IStableSwapRenBtc {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external;

    function remove_liquidity_one_coin(uint256 amount, int128 i, uint256 min_amount) external;

    function get_virtual_price() external view returns (uint256);
}
