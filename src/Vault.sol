// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import 'forge-std/console.sol'; // TODO: remove when done

import 'solmate/tokens/ERC20.sol';
import 'solmate/utils/SafeTransferLib.sol';
import 'solmate/utils/FixedPointMathLib.sol';

import './libraries/Ownership.sol';
import './interfaces/IERC4626.sol';
import './Strategy.sol';

contract Vault is ERC20, IERC4626, Ownership {
	using SafeTransferLib for ERC20;
	using FixedPointMathLib for uint256;

	/// @notice token which the vault uses and accumulates
	ERC20 public immutable asset;
	// uint256 public immutable decimalOffset; // TODO: normalize share decimals to 18 regardless of token decimals?

	uint256 _lockedProfit;
	/// @notice timestamp of last report, used for locked profit calculations
	uint256 public lastReport;
	/// @notice period over which profits are gradually unlocked, defense against sandwich attacks
	uint256 public lockedProfitDuration = 6 hours;
	uint256 public constant MAX_LOCKED_PROFIT_DURATION = 3 days;

	struct StrategyParams {
		bool added;
		uint256 debt;
		uint256 debtRatio;
	}

	Strategy[] _queue;
	mapping(Strategy => StrategyParams) public strategies;

	uint256 internal constant MAX_QUEUE_LENGTH = 20;

	uint256 public totalDebt;
	uint256 public totalDebtRatio;
	uint256 public MAX_TOTAL_DEBT_RATIO = 3_600;

	/*///////////////
	/     Events    /
	///////////////*/

	event Report(Strategy indexed strategy, uint256 gain, uint256 loss);

	event StrategyAdded(Strategy indexed strategy, uint256 debtRatio);

	/*///////////////
	/     Errors    /
	///////////////*/

	error Zero();
	error BelowMinimum(uint256);
	error AboveMaximum(uint256);

	error AlreadyStrategy();
	error NotStrategy();
	error StrategyDoesNotBelongToQueue();
	error StrategyQueueFull();

	constructor(ERC20 _asset, address[] memory _authorized)
		ERC20(
			// e.g. USDC becomes 'Unagii USD Coin Vault v3' and 'uUSDCv3'
			string(abi.encodePacked('Unagii ', _asset.name(), ' Vault v3')),
			string(abi.encodePacked('u', _asset.symbol(), 'v3')),
			18
		)
		Ownership(_authorized)
	{
		asset = _asset;
	}

	/*///////////////////////
	/      Public View      /
  ///////////////////////*/

	function queue() external view returns (Strategy[] memory) {
		return _queue;
	}

	function totalInStrategies() public view returns (uint256 assets) {
		for (uint8 i = 0; i < _queue.length; ++i) {
			assets += strategies[_queue[i]].debt;
		}
	}

	function totalAssets() public view returns (uint256 assets) {
		return asset.balanceOf(address(this)) + totalInStrategies();
	}

	function lockedProfit() public view returns (uint256 lockedAssets) {
		uint256 last = lastReport;
		uint256 duration = lockedProfitDuration;

		unchecked {
			// won't overflow since time is nowhere near uint256.max
			if (block.timestamp >= last + duration) return 0;
			// this can overflow if _lockedProfit * difference > uint256.max but in practice should never happen
			return _lockedProfit - ((_lockedProfit * (block.timestamp - last)) / duration);
		}
	}

	function freeAssets() public view returns (uint256 assets) {
		return totalAssets() - lockedProfit();
	}

	function convertToShares(uint256 _assets) public view returns (uint256 shares) {
		uint256 supply = totalSupply;
		return supply == 0 ? _assets : _assets.mulDivDown(supply, totalAssets());
	}

	function convertToAssets(uint256 _shares) public view returns (uint256 assets) {
		uint256 supply = totalSupply;
		return supply == 0 ? _shares : _shares.mulDivDown(totalAssets(), supply);
	}

	function maxDeposit(address) external pure returns (uint256 assets) {
		return type(uint256).max;
	}

	function previewDeposit(uint256 _assets) public view returns (uint256 shares) {
		return convertToShares(_assets);
	}

	function maxMint(address) external view returns (uint256 shares) {
		return type(uint256).max - totalSupply;
	}

	function previewMint(uint256 shares) public view returns (uint256 assets) {
		uint256 supply = totalSupply;
		return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
	}

	function maxWithdraw(address owner) external view returns (uint256 assets) {
		return convertToAssets(balanceOf[owner]);
	}

	function previewWithdraw(uint256 assets) public view returns (uint256 shares) {
		uint256 supply = totalSupply;
		return supply == 0 ? assets : assets.mulDivUp(supply, freeAssets());
	}

	function maxRedeem(address _owner) external view returns (uint256 shares) {
		return balanceOf[_owner];
	}

	function previewRedeem(uint256 shares) public view returns (uint256 assets) {
		uint256 supply = totalSupply;
		return supply == 0 ? shares : shares.mulDivDown(freeAssets(), supply);
	}

	/*////////////////////////////
	/      Public Functions      /
	////////////////////////////*/

	function safeDeposit(
		uint256 _assets,
		address _receiver,
		uint256 _minShares
	) external returns (uint256 shares) {
		shares = deposit(_assets, _receiver);
		if (shares < _minShares) revert BelowMinimum(shares);
	}

	function safeMint(
		uint256 _shares,
		address _receiver,
		uint256 _maxAssets
	) external returns (uint256 assets) {
		assets = mint(_shares, _receiver);
		if (assets > _maxAssets) revert AboveMaximum(assets);
	}

	function safeWithdraw(
		uint256 _assets,
		address _receiver,
		address _owner,
		uint256 _maxShares
	) external returns (uint256 shares) {
		shares = withdraw(_assets, _receiver, _owner);
		if (shares > _maxShares) revert AboveMaximum(shares);
	}

	function safeRedeem(
		uint256 _shares,
		address _receiver,
		address _owner,
		uint256 _minAssets
	) external returns (uint256 assets) {
		assets = redeem(_shares, _receiver, _owner);
		if (assets < _minAssets) revert BelowMinimum(assets);
	}

	/*////////////////////////////////////
	/      ERC4626 Public Functions      /
	////////////////////////////////////*/

	function deposit(uint256 _assets, address _receiver) public returns (uint256 shares) {
		if ((shares = previewDeposit(_assets)) == 0) revert Zero();

		_deposit(_assets, shares, _receiver);
	}

	function mint(uint256 _shares, address _receiver) public returns (uint256 assets) {
		if (_shares == 0) revert Zero();
		assets = previewMint(_shares);

		_deposit(assets, _shares, _receiver);
	}

	function withdraw(
		uint256 _assets,
		address _receiver,
		address _owner
	) public returns (uint256 shares) {
		if (_assets == 0) revert Zero();
		shares = previewWithdraw(_assets);

		_withdraw(_assets, shares, _owner, _receiver);
	}

	function redeem(
		uint256 _shares,
		address _receiver,
		address _owner
	) public returns (uint256 assets) {
		if ((assets = previewRedeem(_shares)) == 0) revert Zero();

		_withdraw(assets, _shares, _owner, _receiver);
	}

	/*///////////////////////////////////////////
	/      Restricted Functions: onlyOwner      /
	///////////////////////////////////////////*/

	function addStrategy(Strategy _strategy, uint256 _debtRatio) external onlyOwner {
		if (_strategy.vault() != this) revert StrategyDoesNotBelongToQueue();
		if (strategies[_strategy].added) revert AlreadyStrategy();
		if (_queue.length >= MAX_QUEUE_LENGTH) revert StrategyQueueFull();

		totalDebtRatio += _debtRatio;
		if (totalDebtRatio > MAX_TOTAL_DEBT_RATIO) revert AboveMaximum(totalDebtRatio);

		strategies[_strategy] = StrategyParams({added: true, debt: 0, debtRatio: _debtRatio});
		_queue.push(_strategy);

		emit StrategyAdded(_strategy, _debtRatio);
	}

	/*////////////////////////////////////////////
	/      Restricted Functions: onlyAdmins      /
	////////////////////////////////////////////*/

	function removeStrategy(Strategy _strategy) external onlyAdmins {}

	function setDebtRatio(Strategy _strategy, uint256 _newDebtRatio) external onlyAdmins {}

	function setQueue(Strategy[] calldata _newQueue) external onlyAdmins {}

	function setLockedProfitDuration(uint256 _newDuration) external onlyAdmins {}

	/*///////////////////////////////////////////////
	/      Restricted Functions: onlyAuthorized     /
	///////////////////////////////////////////////*/

	function suspendStrategy(Strategy _strategy) external onlyAuthorized {}

	function pause() external onlyAuthorized {}

	function unpause() external onlyAuthorized {}

	/// @dev use if >1 strategy reporting, saves gas
	function reportAll() external onlyAuthorized {
		for (uint8 i = 0; i < _queue.length; ++i) {
			_report(_queue[i]);
		}
		lastReport = block.timestamp;
	}

	function report(Strategy _strategy) external onlyAuthorized {
		if (!strategies[_strategy].added) revert NotStrategy();

		_report(Strategy(_strategy));

		lastReport = block.timestamp;
	}

	/*/////////////////////////////////////////////
	/      Restricted Functions: onlyStrategy     /
	/////////////////////////////////////////////*/

	/*/////////////////////////////
	/      Internal Override      /
	/////////////////////////////*/

	// /// @dev an address cannot mint, burn send or receive share tokens on same block
	// function _mint(address _to, uint256 _amount) internal override useBlockDelay(_to) {
	// 	ERC20._mint(_to, _amount);
	// }

	// /// @dev an address cannot mint, burn send or receive share tokens on same block
	// function _burn(address _from, uint256 _amount) internal override useBlockDelay(_from) {
	// 	ERC20._burn(_from, _amount);
	// }

	// /// @dev an address cannot mint, burn send or receive share tokens on same block
	// function transfer(address _to, uint256 _amount)
	// 	public
	// 	override
	// 	useBlockDelay(msg.sender)
	// 	useBlockDelay(_to)
	// 	returns (bool)
	// {
	// 	return ERC20.transfer(_to, _amount);
	// }

	// /// @dev an address cannot mint, burn send or receive share tokens on same block
	// function transferFrom(
	// 	address _from,
	// 	address _to,
	// 	uint256 _amount
	// ) public override useBlockDelay(_from) useBlockDelay(_to) returns (bool) {
	// 	return ERC20.transferFrom(_from, _to, _amount);
	// }

	/*//////////////////////////////
	/      Internal Functions      /
	//////////////////////////////*/

	function _deposit(
		uint256 _assets,
		uint256 _shares,
		address _receiver
	) internal {
		asset.safeTransferFrom(msg.sender, address(this), _assets);
		_mint(_receiver, _shares);
		emit Deposit(msg.sender, _receiver, _assets, _shares);
	}

	function _withdraw(
		uint256 _assets,
		uint256 _shares,
		address _owner,
		address _receiver
	) internal {
		if (msg.sender != _owner) {
			uint256 allowed = allowance[_owner][msg.sender];
			if (allowed != type(uint256).max) allowance[_owner][msg.sender] = allowed - _shares;
		}

		_burn(_owner, _shares);
		emit Withdraw(msg.sender, _receiver, _owner, _assets, _shares);

		// first, withdraw from balance
		uint256 balance = asset.balanceOf(address(this));

		if (balance > 0) {
			uint256 amount = _assets > balance ? balance : _assets;
			asset.safeTransfer(_receiver, amount);
			_assets -= amount;
		}

		// next, withdraw from strategies
		for (uint8 i = 0; i < _queue.length; ++i) {
			if (_assets == 0) break;
			uint256 received = _collect(_queue[i], _assets, _receiver); // overflow is handled by strategy
			_assets -= received;
		}
	}

	function _lend(Strategy _strategy, uint256 _assets) internal {
		uint256 balance = asset.balanceOf(address(this));
		uint256 amount = _assets > balance ? balance : _assets;

		asset.safeTransfer(address(_strategy), amount);
		_strategy.invest();

		strategies[_strategy].debt += amount;
		totalDebt += amount;
	}

	function _collect(
		Strategy _strategy,
		uint256 _assets,
		address _receiver
	) internal returns (uint256 received) {
		received = _strategy.withdraw(_assets, _receiver); // strategy handles overflow

		uint256 debt = strategies[_strategy].debt;

		uint256 amount = debt > received ? received : debt;

		strategies[_strategy].debt -= amount;
		totalDebt -= amount;
	}

	function _report(Strategy _strategy) internal {
		uint256 assets = _strategy.totalAssets();
		uint256 debt = strategies[_strategy].debt;

		uint256 gain;

		if (assets > debt) {
			unchecked {
				gain = assets - debt;
			}
			totalDebt += gain;

			_lockedProfit = lockedProfit() + gain;
		} else if (debt > assets) {
			unchecked {
				uint256 loss = debt - assets;
				totalDebt -= loss;

				uint256 lockedProfitBeforeLoss = lockedProfit();
				_lockedProfit = lockedProfitBeforeLoss > loss ? lockedProfitBeforeLoss - loss : 0;
			}
		}

		strategies[_strategy].debt = assets;

		uint256 possibleDebt = totalDebtRatio == 0
			? 0
			: (totalAssets() * strategies[_strategy].debtRatio) / totalDebtRatio;

		if (possibleDebt > assets) _lend(_strategy, possibleDebt - assets);
		else if (assets > possibleDebt) _collect(_strategy, assets - possibleDebt, address(this));
	}
}
