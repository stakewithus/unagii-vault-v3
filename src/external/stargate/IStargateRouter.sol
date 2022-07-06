// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IStargateRouter {
	struct lzTxObj {
		uint256 dstGasForCall;
		uint256 dstNativeAmount;
		bytes dstNativeAddr;
	}

	function addLiquidity(
		uint256 _poolId,
		uint256 _amountLD,
		address _to
	) external;

	function instantRedeemLocal(
		uint16 _srcPoolId,
		uint256 _amountLP,
		address _to
	) external returns (uint256);

	function redeemLocal(
		uint256 _dstChainId,
		uint256 _srcPoolId,
		uint256 _dstPoolId,
		address payable _refundAddress,
		uint256 _amountLP,
		bytes calldata _to,
		lzTxObj memory _lzTxParams
	) external payable;
}
