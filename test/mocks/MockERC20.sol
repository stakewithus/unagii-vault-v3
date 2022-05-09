// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import 'solmate/tokens/ERC20.sol';

/** ERC20 which canyone can mint */
contract MockERC20 is ERC20 {
	constructor(
		string memory _name,
		string memory _symbol,
		uint8 _decimals
	) ERC20(_name, _symbol, _decimals) {}

	function mint(address to, uint256 amount) external {
		_mint(to, amount);
	}

	function burn(address from, uint256 amount) external {
		_burn(from, amount);
	}
}
