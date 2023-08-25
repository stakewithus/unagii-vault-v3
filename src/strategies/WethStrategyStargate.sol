// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.9;

import "forge-std/console.sol";

import {WETH} from "solmate/tokens/WETH.sol";
import {IStargateRouter, ILPStaking, LPTokenERC20} from "../external/stargate/Interfaces.sol";
import "../Swap.sol";
import "../Strategy.sol";

contract WethStrategyStargate is Strategy {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for LPTokenERC20;
    using SafeTransferLib for WETH;
    using FixedPointMathLib for uint256;

    IStargateRouter internal constant router = IStargateRouter(0x8731d54E9D02c286767d56ac03e8037C07e01e98);
    ILPStaking internal constant staking = ILPStaking(0xB0D502E938ed5f4df2E681fE6E419ff29631d62b);
    ERC20 internal constant STG = ERC20(0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6);

    /// @dev Stargate's version of WETH that automatically unwraps on transfer. Annoyingly, not canonical WETH
    WETH internal constant SGETH = WETH(payable(0x72E2F4830b9E45d52F80aC08CB2bEC0FeF72eD9c));
    /// @dev canonical WETH
    WETH internal constant WETH9 = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    /// @dev pid of asset in their router
    uint16 public constant routerPoolId = 13;
    /// @dev pid of asset in their LP staking contract
    uint256 public constant stakingPoolId = 2;
    LPTokenERC20 public constant lpToken = LPTokenERC20(0x101816545F6bd2b1076434B54383a1E633390A2E);

    /// @notice contract used to swap STG rewards to asset
    Swap public swap;

    /*///////////////
    /     Errors    /
    ///////////////*/

    error NoRewards();
    error NothingToInvest();
    error BelowMinimum(uint256);
    error InvalidAsset();

    constructor(
        Vault _vault,
        address _treasury,
        address _nominatedOwner,
        address _admin,
        address[] memory _authorized,
        Swap _swap
    ) Strategy(_vault, _treasury, _nominatedOwner, _admin, _authorized) {
        swap = _swap;

        if (address(_vault.asset()) != address(WETH9)) revert InvalidAsset();

        _approve();
    }

    receive() external payable {
        if (msg.sender == address(WETH9)) return; // do nothing when unwrapping WETH

        // SGETH automatically unwraps to ETH upon transfer in `redeemLocal` and `instantRedeemLocal`. We wrap and send
        // WETH from other sources (namely router) to vault as ETH.
        WETH9.deposit{value: msg.value}();
        asset.safeTransfer(address(vault), msg.value);
    }

    /*///////////////////////
    /      Public View      /
    ///////////////////////*/

    function totalAssets() public view override returns (uint256 assets) {
        (uint256 stakedBalance,) = staking.userInfo(stakingPoolId, address(this));
        return lpToken.amountLPtoLD(stakedBalance);
    }

    /*///////////////////////////////////////////
    /      Restricted Functions: onlyOwner      /
    ///////////////////////////////////////////*/

    function changeSwap(Swap _swap) external onlyOwner {
        _unapproveSwap();
        swap = _swap;
        _approveSwap();
    }

    /*////////////////////////////////////////////////
    /      Restricted Functions: onlyAuthorized      /
    ////////////////////////////////////////////////*/

    function reapprove() external onlyAuthorized {
        _unapprove();
        _approve();
    }

    /**
     * @notice Safeguard to manually withdraw if insufficient delta in Stargate local pool.
     * 	@dev Use router.quoteLayerZeroFee to estimate 'msg.value' (excess will be refunded to `msg.sender`).
     * 	@param _dstChainId STG chainId, see https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet, ideally we want to use the chain with cheapest gas
     * 	@param _assets amount of LP to redeem, use type(uint256).max to withdraw everything
     * 	@param _lzTxObj usually can just be (0, 0, "0x")
     */
    function manualWithdraw(uint16 _dstChainId, uint256 _assets, IStargateRouter.lzTxObj calldata _lzTxObj)
        external
        payable
        onlyAuthorized
    {
        uint256 assets = totalAssets();

        uint256 amount = assets > _assets ? _assets : assets;
        uint256 lpAmount = _convertAssetToLP(amount);

        staking.withdraw(stakingPoolId, lpAmount);

        router.redeemLocal{value: msg.value}(
            _dstChainId,
            routerPoolId,
            routerPoolId,
            payable(msg.sender),
            lpAmount,
            abi.encodePacked(address(this)),
            _lzTxObj
        );
    }

    /*/////////////////////////////
    /      Internal Override      /
    /////////////////////////////*/

    function _withdraw(uint256 _assets) internal override returns (uint256 received) {
        uint256 lpAmount = _convertAssetToLP(_assets);

        // lpAmount can round down to 0 which will cause the withdraw to fail
        if (lpAmount == 0) return received;

        // 1. withdraw from staking contract
        staking.withdraw(stakingPoolId, lpAmount);

        // withdraw from stargate router
        received = router.instantRedeemLocal(routerPoolId, lpAmount, address(this));
        if (received < _calculateSlippage(_assets)) revert BelowMinimum(received);
    }

    function _harvest() internal override {
        // empty deposit/withdraw claims rewards withdraw as with all Goose clones
        staking.withdraw(stakingPoolId, 0);

        uint256 rewardBalance = STG.balanceOf(address(this));
        if (rewardBalance == 0) revert NoRewards(); // nothing to harvest

        swap.swapTokens(address(STG), address(asset), rewardBalance, 1);
    }

    function _invest() internal override {
        uint256 assetBalance = asset.balanceOf(address(this));
        if (assetBalance == 0) revert NothingToInvest();

        WETH9.withdraw(assetBalance);
        SGETH.deposit{value: assetBalance}();

        router.addLiquidity(routerPoolId, assetBalance, address(this));

        uint256 balance = lpToken.balanceOf(address(this));

        if (balance < _calculateSlippage(assetBalance)) revert BelowMinimum(balance);

        staking.deposit(stakingPoolId, balance);
    }

    /*//////////////////////////////
    /      Internal Functions      /
    //////////////////////////////*/

    function _approve() internal {
        // approve deposit SGETH into router
        SGETH.safeApprove(address(router), type(uint256).max);
        // approve deposit lpToken into staking contract
        lpToken.safeApprove(address(staking), type(uint256).max);

        _approveSwap();
    }

    function _unapprove() internal {
        SGETH.safeApprove(address(router), 0);
        lpToken.safeApprove(address(staking), 0);

        _unapproveSwap();
    }

    // approve swap rewards to asset
    function _unapproveSwap() internal {
        STG.safeApprove(address(swap), 0);
    }

    // approve swap rewards to asset
    function _approveSwap() internal {
        STG.safeApprove(address(swap), type(uint256).max);
    }

    function _convertAssetToLP(uint256 _amount) internal view returns (uint256) {
        return _amount.mulDivDown(lpToken.totalSupply(), lpToken.totalLiquidity());
    }
}
