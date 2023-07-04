// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.9;

import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "./external/uniswap/ISwapRouter02.sol";
import "./external/sushiswap/ISushiRouter.sol";
import {IAsset, IVault} from "./external/balancer/IVault.sol";
import "./libraries/Ownable.sol";
import "./libraries/Path.sol";

/**
 * @notice
 * Swap contract used by strategies to:
 * 1. swap strategy rewards to 'asset'
 * 2. zap similar tokens to asset (e.g. USDT to USDC)
 */
contract Swap is Ownable {
    using SafeTransferLib for ERC20;
    using Path for bytes;

    enum Route {
        Unsupported,
        UniswapV2,
        UniswapV3Direct,
        UniswapV3Path,
        SushiSwap,
        BalancerBatch,
        BalancerSingle
    }

    /**
     * @dev info depends on route:
     * 		UniswapV2: address[] path
     * 		UniswapV3Direct: uint24 fee
     * 		UniswapV3Path: bytes path (address, uint24 fee, address, uint24 fee, address)
     */
    struct RouteInfo {
        Route route;
        bytes info;
    }

    ISushiRouter internal constant sushiswap = ISushiRouter(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);
    /// @dev single address which supports both uniswap v2 and v3 routes
    ISwapRouter02 internal constant uniswap = ISwapRouter02(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    IVault internal constant balancer = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    /// @dev tokenIn => tokenOut => routeInfo
    mapping(address => mapping(address => RouteInfo)) public routes;

    /*//////////////////
    /      Events      /
    //////////////////*/

    event RouteSet(address indexed tokenIn, address indexed tokenOut, RouteInfo routeInfo);
    event RouteRemoved(address indexed tokenIn, address indexed tokenOut);

    /*//////////////////
    /      Errors      /
    //////////////////*/

    error UnsupportedRoute(address tokenIn, address tokenOut);
    error InvalidRouteInfo();

    constructor() Ownable() {
        address CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        address CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        address LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;

        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        address STG = 0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

        address BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
        address AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

        _setRoute(CRV, WETH, RouteInfo({route: Route.UniswapV3Direct, info: abi.encode(uint24(3_000))}));
        _setRoute(CVX, WETH, RouteInfo({route: Route.UniswapV3Direct, info: abi.encode(uint24(10_000))}));
        _setRoute(LDO, WETH, RouteInfo({route: Route.UniswapV3Direct, info: abi.encode(uint24(3_000))}));

        _setRoute(CRV, USDC, RouteInfo({route: Route.UniswapV3Direct, info: abi.encode(uint24(10_000))}));
        _setRoute(
            CVX,
            USDC,
            RouteInfo({route: Route.UniswapV3Path, info: abi.encodePacked(CVX, uint24(10_000), WETH, uint24(500), USDC)})
        );

        _setRoute(USDC, USDT, RouteInfo({route: Route.UniswapV3Direct, info: abi.encode(uint24(100))}));

        // STG -> bb-a-USD -> bb-a-USDC -> USDC
        IAsset[] memory stgUsdcAssets = new IAsset[](4);
        stgUsdcAssets[0] = IAsset(STG);
        stgUsdcAssets[1] = IAsset(0xfeBb0bbf162E64fb9D0dfe186E517d84C395f016); // bb-a-USD
        stgUsdcAssets[2] = IAsset(0xcbFA4532D8B2ade2C261D3DD5ef2A2284f792692); // bb-a-USDC
        stgUsdcAssets[3] = IAsset(USDC);

        bytes32[] memory stgUsdcPoolIds = new bytes32[](3);
        stgUsdcPoolIds[0] = 0x639883476960a23b38579acfd7d71561a0f408cf000200000000000000000505; // STG -> bb-a-USD
        stgUsdcPoolIds[1] = 0xfebb0bbf162e64fb9d0dfe186e517d84c395f016000000000000000000000502; // bb-a-USD -> bb-a-USDC
        stgUsdcPoolIds[2] = 0xcbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000004fa; // bb-a-USDC -> USDC

        IVault.BatchSwapStep[] memory stgUsdcSteps = _constructBalancerBatchSwapSteps(stgUsdcPoolIds);

        _setRoute(STG, USDC, RouteInfo({route: Route.BalancerBatch, info: abi.encode(stgUsdcSteps, stgUsdcAssets)}));

        // STG -> bb-a-USD -> wstETH -> WETH
        IAsset[] memory stgWethAssets = new IAsset[](6);
        stgWethAssets[0] = IAsset(STG);
        stgWethAssets[1] = IAsset(0xfeBb0bbf162E64fb9D0dfe186E517d84C395f016); // bb-a-USD
        stgWethAssets[2] = IAsset(0xcbFA4532D8B2ade2C261D3DD5ef2A2284f792692); // bb-a-USDC
        stgWethAssets[3] = IAsset(USDC);
        stgWethAssets[4] = IAsset(0x79c58f70905F734641735BC61e45c19dD9Ad60bC); // USDC-DAI-USDT
        stgWethAssets[5] = IAsset(WETH);

        bytes32[] memory stgWethPoolIds = new bytes32[](5);
        stgWethPoolIds[0] = 0x639883476960a23b38579acfd7d71561a0f408cf000200000000000000000505; // STG -> bb-a-USD
        stgWethPoolIds[1] = 0xfebb0bbf162e64fb9d0dfe186e517d84c395f016000000000000000000000502; // bb-a-USD -> bb-a-USDC
        stgWethPoolIds[2] = 0xcbfa4532d8b2ade2c261d3dd5ef2a2284f7926920000000000000000000004fa; // bb-a-USDC -> USDC
        stgWethPoolIds[3] = 0x79c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7; // USDC -> USDC-DAI-USDT
        stgWethPoolIds[4] = 0x08775ccb6674d6bdceb0797c364c2653ed84f3840002000000000000000004f0; // USDC-DAI-USDT -> WETH

        IVault.BatchSwapStep[] memory stgWethSteps = _constructBalancerBatchSwapSteps(stgWethPoolIds);

        _setRoute(STG, WETH, RouteInfo({route: Route.BalancerBatch, info: abi.encode(stgWethSteps, stgWethAssets)}));

        bytes32 balWethPoolId = 0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014;
        _setRoute(BAL, WETH, RouteInfo({route: Route.BalancerSingle, info: abi.encode(balWethPoolId)}));

        bytes32 auraWethPoolId = 0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274;
        _setRoute(AURA, WETH, RouteInfo({route: Route.BalancerSingle, info: abi.encode(auraWethPoolId)}));
    }

    /*///////////////////////
    /      Public View      /
    ///////////////////////*/

    function getRoute(address _tokenIn, address _tokenOut) external view returns (RouteInfo memory routeInfo) {
        return routes[_tokenIn][_tokenOut];
    }

    /*////////////////////////////
    /      Public Functions      /
    ////////////////////////////*/

    function swapTokens(address _tokenIn, address _tokenOut, uint256 _amount, uint256 _minReceived)
        external
        returns (uint256 received)
    {
        RouteInfo memory routeInfo = routes[_tokenIn][_tokenOut];

        ERC20 tokenIn = ERC20(_tokenIn);
        tokenIn.safeTransferFrom(msg.sender, address(this), _amount);

        Route route = routeInfo.route;
        bytes memory info = routeInfo.info;

        if (route == Route.UniswapV2) {
            received = _uniswapV2(_amount, _minReceived, info);
        } else if (route == Route.UniswapV3Direct) {
            received = _uniswapV3Direct(_tokenIn, _tokenOut, _amount, _minReceived, info);
        } else if (route == Route.UniswapV3Path) {
            received = _uniswapV3Path(_amount, _minReceived, info);
        } else if (route == Route.SushiSwap) {
            received = _sushiswap(_amount, _minReceived, info);
        } else if (route == Route.BalancerBatch) {
            received = _balancerBatch(_amount, _minReceived, info);
        } else if (route == Route.BalancerSingle) {
            received = _balancerSingle(_tokenIn, _tokenOut, _amount, _minReceived, info);
        } else {
            revert UnsupportedRoute(_tokenIn, _tokenOut);
        }

        // return unswapped amount to sender
        uint256 balance = tokenIn.balanceOf(address(this));
        if (balance > 0) tokenIn.safeTransfer(msg.sender, balance);
    }

    /*///////////////////////////////////////////
    /      Restricted Functions: onlyOwner      /
    ///////////////////////////////////////////*/

    function setRoute(address _tokenIn, address _tokenOut, RouteInfo memory _routeInfo) external onlyOwner {
        _setRoute(_tokenIn, _tokenOut, _routeInfo);
    }

    function unsetRoute(address _tokenIn, address _tokenOut) external onlyOwner {
        delete routes[_tokenIn][_tokenOut];
        emit RouteRemoved(_tokenIn, _tokenOut);
    }

    /*//////////////////////////////
    /      Internal Functions      /
    //////////////////////////////*/

    function _setRoute(address _tokenIn, address _tokenOut, RouteInfo memory _routeInfo) internal {
        Route route = _routeInfo.route;
        bytes memory info = _routeInfo.info;

        if (route == Route.UniswapV2 || route == Route.SushiSwap) {
            address[] memory path = abi.decode(info, (address[]));

            if (path[0] != _tokenIn) revert InvalidRouteInfo();
            if (path[path.length - 1] != _tokenOut) revert InvalidRouteInfo();
        }

        // just check that this doesn't throw an error
        if (route == Route.UniswapV3Direct) abi.decode(info, (uint24));

        if (route == Route.UniswapV3Path) {
            bytes memory path = info;

            // check first tokenIn
            (address tokenIn,,) = path.decodeFirstPool();
            if (tokenIn != _tokenIn) revert InvalidRouteInfo();

            // check last tokenOut
            while (path.hasMultiplePools()) path = path.skipToken();
            (, address tokenOut,) = path.decodeFirstPool();
            if (tokenOut != _tokenOut) revert InvalidRouteInfo();
        }

        // just check that these don't throw an error, i.e. the poolId contains both _tokenIn
        if (route == Route.BalancerSingle) {
            bytes32 poolId = abi.decode(info, (bytes32));
            balancer.getPoolTokenInfo(poolId, _tokenIn);
            balancer.getPoolTokenInfo(poolId, _tokenOut);
        }

        address router = _getRouterAddress(route);

        ERC20(_tokenIn).safeApprove(router, 0);
        ERC20(_tokenIn).safeApprove(router, type(uint256).max);

        routes[_tokenIn][_tokenOut] = _routeInfo;
        emit RouteSet(_tokenIn, _tokenOut, _routeInfo);
    }

    function _uniswapV2(uint256 _amount, uint256 _minReceived, bytes memory _path) internal returns (uint256) {
        address[] memory path = abi.decode(_path, (address[]));

        return uniswap.swapExactTokensForTokens(_amount, _minReceived, path, msg.sender);
    }

    function _sushiswap(uint256 _amount, uint256 _minReceived, bytes memory _path) internal returns (uint256) {
        address[] memory path = abi.decode(_path, (address[]));

        uint256[] memory received =
            sushiswap.swapExactTokensForTokens(_amount, _minReceived, path, msg.sender, type(uint256).max);

        return received[received.length - 1];
    }

    function _uniswapV3Direct(
        address _tokenIn,
        address _tokenOut,
        uint256 _amount,
        uint256 _minReceived,
        bytes memory _info
    ) internal returns (uint256) {
        uint24 fee = abi.decode(_info, (uint24));

        return uniswap.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: fee,
                recipient: msg.sender,
                amountIn: _amount,
                amountOutMinimum: _minReceived,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function _uniswapV3Path(uint256 _amount, uint256 _minReceived, bytes memory _path) internal returns (uint256) {
        return uniswap.exactInput(
            ISwapRouter02.ExactInputParams({
                path: _path,
                recipient: msg.sender,
                amountIn: _amount,
                amountOutMinimum: _minReceived
            })
        );
    }

    function _balancerBatch(uint256 _amount, uint256 _minReceived, bytes memory _info) internal returns (uint256) {
        (IVault.BatchSwapStep[] memory steps, IAsset[] memory assets) =
            abi.decode(_info, (IVault.BatchSwapStep[], IAsset[]));

        steps[0].amount = _amount;

        int256[] memory limits = new int256[](assets.length);

        limits[0] = int256(_amount);
        limits[limits.length - 1] = -int256(_minReceived);

        int256[] memory received = balancer.batchSwap(
            IVault.SwapKind.GIVEN_IN,
            steps,
            assets,
            IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(msg.sender)),
                toInternalBalance: false
            }),
            limits,
            type(uint256).max
        );

        return uint256(-received[received.length - 1]);
    }

    function _balancerSingle(
        address _tokenIn,
        address _tokenOut,
        uint256 _amount,
        uint256 _minReceived,
        bytes memory _info
    ) internal returns (uint256) {
        bytes32 poolId = abi.decode(_info, (bytes32));

        return balancer.swap(
            IVault.SingleSwap({
                poolId: poolId,
                kind: IVault.SwapKind.GIVEN_IN,
                assetIn: IAsset(_tokenIn),
                assetOut: IAsset(_tokenOut),
                amount: _amount,
                userData: ""
            }),
            IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(msg.sender)),
                toInternalBalance: false
            }),
            _minReceived,
            type(uint256).max
        );
    }

    function _getRouterAddress(Route _route) internal pure returns (address) {
        if (_route == Route.SushiSwap) {
            return address(sushiswap);
        } else if (_route == Route.UniswapV2 || _route == Route.UniswapV3Direct || _route == Route.UniswapV3Path) {
            return address(uniswap);
        } else if (_route == Route.BalancerBatch || _route == Route.BalancerSingle) {
            return address(balancer);
        } else {
            revert InvalidRouteInfo();
        }
    }

    function _constructBalancerBatchSwapSteps(bytes32[] memory _poolIds)
        internal
        pure
        returns (IVault.BatchSwapStep[] memory steps)
    {
        uint256 length = _poolIds.length;
        steps = new IVault.BatchSwapStep[](length);

        for (uint8 i = 0; i < length; ++i) {
            steps[i] = IVault.BatchSwapStep({
                poolId: _poolIds[i],
                assetInIndex: i,
                assetOutIndex: i + 1,
                amount: 0,
                userData: ""
            });
        }
    }
}
