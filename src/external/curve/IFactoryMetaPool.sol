//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

// https://curve.readthedocs.io/factory-pools.html

import "solmate/tokens/ERC20.sol";

abstract contract IFactoryMetaPool is ERC20 {
    function get_virtual_price() external view virtual returns (uint256);
}
