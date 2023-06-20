// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;

import 'forge-std/console.sol';
import 'forge-std/Script.sol';

import 'src/strategies/UsdcStrategyCompound.sol';

contract Deploy is Script {
	Swap swap = Swap(vm.envAddress('SWAP_ADDRESS'));
	address treasury = vm.envAddress('TREASURY_ADDRESS');
	address multisig = vm.envAddress('MULTISIG_ADDRESS');
	address timeLock = vm.envAddress('TIMELOCK_ADDRESS');
	address[] authorized = vm.envAddress('AUTH_ADDRESSES', ',');
	Vault usdcVault = Vault(0x09DAb27cC3758040eea0f7b51df2Aee14bc003D6);

	function run() external {
		vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

		new UsdcStrategyCompound(usdcVault, treasury, timeLock, multisig, authorized, swap);

		vm.stopBroadcast();
	}
}

// swap from Stargate to Compound strategy
contract Setup is Script {
	Swap swap = Swap(vm.envAddress('SWAP_ADDRESS'));
	address treasury = vm.envAddress('TREASURY_ADDRESS');
	address multisig = vm.envAddress('MULTISIG_ADDRESS');
	address timeLock = vm.envAddress('TIMELOCK_ADDRESS');
	address[] authorized = vm.envAddress('AUTH_ADDRESSES', ',');
	Vault usdcVault = Vault(vm.envAddress('USDC_VAULT'));
	Strategy usdcStrategyStargate = Strategy(vm.envAddress('USDC_STRATEGY_STARGATE'));
	UsdcStrategyCompound usdcStrategyCompound = UsdcStrategyCompound(vm.envAddress('USDC_STRATEGY_COMPOUND'));

	address constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
	address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
	address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

	function run() external {
		vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

		// send like 0.01 USDC (not S*USDC) first to strategy and call invest to handle strategy's zero error
		// usdcStrategyStargate.invest();

		// usdcVault.removeStrategy(usdcStrategyStargate, false, 0);
		// usdcVault.addStrategy(usdcStrategyCompound, 95);
		// usdcVault.report(usdcStrategyCompound);

		// setup swap COMP -> USDC
		address[] memory path = new address[](3);
		path[0] = COMP;
		path[1] = WETH;
		path[2] = USDC;

		swap.setRoute(
			address(COMP),
			address(USDC),
			Swap.RouteInfo({route: Swap.Route.SushiSwap, info: abi.encode(path)})
		);

		vm.stopBroadcast();
	}
}

contract GetHealth is Script {
	UsdcStrategyCompound usdcStrategyCompound = UsdcStrategyCompound(vm.envAddress('USDC_STRATEGY_COMPOUND'));

	function run() external {
		vm.startBroadcast(vm.envUint('PRIVATE_KEY'));
		(
			uint256 supplied,
			uint256 borrowed,
			uint256 marketCol,
			uint256 safeCol,
			uint256 collateralRatio
		) = usdcStrategyCompound.getHealth();

		console.log(supplied);
		console.log(borrowed);
		console.log(marketCol);
		console.log(safeCol);
		console.log(collateralRatio);

		vm.stopBroadcast();
	}
}

contract Report is Script {
	Vault usdcVault = Vault(vm.envAddress('USDC_VAULT'));
	UsdcStrategyCompound usdcStrategyCompound = UsdcStrategyCompound(vm.envAddress('USDC_STRATEGY_COMPOUND'));

	function run() external {
		vm.startBroadcast(vm.envUint('PRIVATE_KEY'));

		usdcVault.reportAll();
		// usdcStrategyCompound.setBufferAndRebalance(1e18);

		vm.stopBroadcast();
	}
}
