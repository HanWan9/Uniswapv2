pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './libraries/UniswapV2Library.sol';
import './interfaces/IUniswapV2Router01.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

contract UniswapV2Router01 is IUniswapV2Router01 {
    // 部署时定义的常量工厂地址和WETH地址
    address public immutable override factory;
    address public immutable override WETH;

    // 修饰符：确保deadline大于当前区块时间
    modifier ensure(uint deadline) {
        // solhint-disable-next-line security/no-block-members
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    // 构造函数, 传入工厂地址和WETH地址
    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    // 退款方法
    receive() external payable {
        // 断言调用者为WETH地址
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    /**
     * @dev 添加流动性的私有方法
     * @param tokenA tokenA地址
     * @param tokenB tokenB地址
     * @param amountADesired 期望数量A
     * @param amountBDesired 期望数量B
     * @param amountAMin 最小数量A
     * @param amountBMin 最小数量B
     * @return amountA 数量A
     * @return amountB 数量B
     */
    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) private returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        // 如果交易对不存在，则创建交易对
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        // 获取储备量reserve{A,B}
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        // 如果储备量reserve{A,B} == 0
        if (reserveA == 0 && reserveB == 0) {
            // 数量amount{A,B} = 期望数量A,B
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // 最优数量B = 期望数量A * 储备量B / 储备量A
            uint256 amountBOptimal = UniswapV2Library.quote(
                amountADesired, 
                reserveA, 
                reserveB
            );
            // 如果最优数量B <= 期望数量B
            if (amountBOptimal <= amountBDesired) {
                // 确认最优数量B >= 最小数量B
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                // 数量{A,B} = 期望数量A，最优数量B
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                // 最优数量A = 期望数量B * 储备量A / 储备量B
                uint256 amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                // 断言最优数量A <= 期望数量A
                assert(amountAOptimal <= amountADesired);
                // 确认最优数量A >= 最小数量A
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                // 数量{A,B} = 最优数量A，期望数量B
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    /**
     * @dev 添加流动性方法
     * @param tokenA tokenA地址
     * @param tokenB tokenB地址
     * @param amountADesired 期望数量A
     * @param amountBDesired 期望数量B
     * @param amountAMin 最小数量A
     * @param amountBMin 最小数量B
     * @param to to地址
     * @param deadline 最后期限
     * @return amountA 数量A
     * @return amountB 数量B
     * @return liquidity 流动性数量
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) 
        external 
        override 
        ensure(deadline) 
        returns (
            uint256 amountA, 
            uint256 amountB, 
            uint256 liquidity
        ) 
    {
        // 获取数量A，数量B
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        // 根据TokenA地址，TokenB地址，获取"pair合约"地址
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 将数量为amountA的tokenA从msg.sender账户中安全发送到pair合约地址
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        // 将数量为amountB的tokenB从msg.sender账户中安全发送到pair合约地址
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        // 流动性数量 = pair合约的铸造方法铸造给to地址的返回值
        liquidity = IUniswapV2Pair(pair).mint(to);
    }
    /**
     * @dev 添加ETH流动性方法
     * @param token token地址
     * @param amountTokenDesired token期望数量 
     * @param amountTokenMin token最小数量
     * @param amountETHMin ETH最小数量
     * @param to to地址
     * @param deadline 最后期限
     * @return amountToken token数量
     * @return amountETH ETH数量
     * @return liquidity 流动性数量
     */
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external override payable ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        // 获取Token数量，ETH数量
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        // 根据Token地址，WETH地址，获取"pair合约"地址
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        // 将"token数量"的token从msg.sender账户中安全发送到pair合约地址
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        // 向"WETH合约"存款"ETH数量"的主币
        IWETH(WETH).deposit{value: amountETH}();
        // 将"ETH数量"的WETH从msg.sender账户中安全发送到pair合约地址
        assert(IWETH(WETH).transfer(pair, amountETH));
        // 流动性数量 = pair合约的铸造方法铸造给to地址的返回值
        liquidity = IUniswapV2Pair(pair).mint(to);
        // 如果‘收到的主币数量’ > ‘ETH数量’，则返还‘收到的主币数量’ - ‘ETH数量’
        if (msg.value > amountETH) 
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH); // refund dust eth, if any
    }

    /**
     * @dev 移除流动性方法
     * @param tokenA tokenA地址
     * @param tokenB tokenB地址
     * @param liquidity 流动性数量
     * @param amountAMin 最小数量A
     * @param amountBMin 最小数量B
     * @param to to地址
     * @param deadline 最后期限
     * @return amountA 数量A
     * @return amountB 数量B
     */
    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        // 计算tokenA, tokenB的CREATE2地址,而无需进行任何外部调用
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 将流动性数量从用户发送到pair合约地址（需提前批准）
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        // pair合约销毁流动性数量，并将数值0,1的token发送到to地址
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        // 排序tokenA，tokenB
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        // 按排序后的token顺序返回数值A，B
        (amountA, amountB) = tokenA == token0 
            ? (amount0, amount1) 
            : (amount1, amount0);
        // 确认数值A,B >= 最小数量A,B
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }
    /**
     * @dev 移除ETH流动性方法
     * @param token token地址
     * @param liquidity 流动性数量
     * @param amountTokenMin token最小数量
     * @param amountETHMin ETH最小数量
     * @param to to地址
     * @param deadline 最后期限
     * @return amountToken token数量
     * @return amountETH ETH数量
     */
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        // (token数量，ETH数量) = 移除流动性(token地址，WETH地址，流动性数量，token最小数量，ETH最小数量，to地址，最后期限)
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        // 将token数量的token发送到to地址
        TransferHelper.safeTransfer(token, to, amountToken);
        // 从WETH合约中提取ETH数量的主币
        IWETH(WETH).withdraw(amountETH);
        // 将ETH数量的主币发送到to地址
        TransferHelper.safeTransferETH(to, amountETH);
    }

    /**
     * @dev 带签名移除流动性
     * @param tokenA tokenA地址
     * @param tokenB tokenB地址
     * @param liquidity 流动性数量
     * @param amountAMin 最小数量A
     * @param amountBMin 最小数量B
     * @param to to地址
     * @param deadline 最后期限
     * @param approveMax 全部批准
     * @param v v,r,s 实质为签名（approve操作可以变成一个签名）
     * @param r 
     * @param s 
     * @return amountA 数量A
     * @return amountB 数量B
     */
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external override returns (uint256 amountA, uint256 amountB) {
        // 计算tokenA, tokenB的CREATE2地址,而无需进行任何外部调用
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        // 如果全部批准，value值等于最大uint256，否则等于流动性
        uint256 value = approveMax ? uint256(-1) : liquidity;
        // 调用pair合约的permit方法，传入(调用账户，当前合约地址，数值，最后期限，v，r，s)
        IUniswapV2Pair(pair).permit(
            msg.sender, 
            address(this), 
            value, 
            deadline, 
            v, 
            r, 
            s
        );
        // (数量A，数量B) = 移除流动性(tokenA地址，tokenB地址，流动性数量，最小数量A，最小数量B，to地址，最后期限)
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    /**
     * @dev 带签名移除ETH流动性
     * @param token token地址
     * @param liquidity 流动性数量
     * @param amountTokenMin token最小数量
     * @param amountETHMin ETH最小数量
     * @param to to地址
     * @param deadline 最后期限
     * @param approveMax 全部批准
     * @param v 
     * @param r 
     * @param s 
     * @return amountToken token数量
     * @return amountETH ETH数量
     */
    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external override returns (uint256 amountToken, uint256 amountETH) {
        // 计算token, WETH的CREATE2地址,而无需进行任何外部调用
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        // 如果全部批准，value值等于最大uint256，否则等于流动性
        uint256 value = approveMax ? uint(-1) : liquidity;
        // 调用pair合约的许可方法，传入(调用账户，当前合约地址，数值，最后期限，v，r，s)
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        // (token数量，ETH数量) = 移除ETH流动性(token地址，流动性数量，token最小数量，ETH最小数量，to地址，最后期限)
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** SWAP ****
    /**
     * @dev 私有交换方法
     * @param amounts 要求初始金额已经发送到第一对
     * @param path 路径数组
     * @param _to to地址
     */
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, address[] memory path, address _to) private {
        // 遍历路径数组
        for (uint i; i < path.length - 1; i++) {
            // (输入地址，输出地址) = (当前地址，下一个地址)
            (address input, address output) = (path[i], path[i + 1]);
            // token0 = 排序(输入地址，输出地址)
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            // 输出数量 = 数额数组下一个数额
            uint256 amountOut = amounts[i + 1];
            // (输出数额0，输出数额1) = 输入地址 == token0 ? (0，输出数额) : (输出数额，0)
            (uint256 amount0Out, uint256 amount1Out) = input == token0 
                ? (uint256(0), amountOut) 
                : (amountOut, uint256(0));
            // to地址 = i < 路径数组长度 - 2 ? (输出地址，路径下下个地址)的pair合约地址 : _to地址
            address to = i < path.length - 2 
                ? UniswapV2Library.pairFor(factory, output, path[i + 2]) 
                : _to;
            // 调用(输入地址，输出地址)的pair合约地址的交换方法，传入(输出数额0，输出数额1，to地址，0x00(用于闪电交换))
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output))
                .swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }



    // 以下有具体的六中交换方法
    /**
     * @dev 根据精确的token交换尽量多的token
     * @param amountIn 精确输入数额
     * @param amountOutMin 最小输出数额
     * @param path 路径数组
     * @param to to地址
     * @param deadline 最后期限
     * @return amounts[] 数额数组
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        // 数额数组 = 遍历路径数组((输入数额 * 997 * 储备量Out) / (储备量In * 1000 + 输入数额 * 997))
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        // 确认数额数组最后一个元素 >= 最小输出数额
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 将数量为数额数组[0]的路径[0]的token从调用者账户发送到(路径0,路径1)的pair合约地址
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        // 私有交换方法(数额数组，路径数组，to地址)
        _swap(amounts, path, to);
    }

    /**
     * @dev 使用尽量少的token交换精确的token，相当于给输出，求输入
     * @param amountOut 精确输出数额
     * @param amountInMax 最大输入数额
     * @param path 路径数组
     * @param to to地址
     * @param deadline 最后期限
     * @return amounts[] 数额数组
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        // 数额数组 ≈ 遍历路径数组((储备量In*储备量Out * 1000) / (储备量Out - 输出数额*997)+1)
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 确认数额数组第一个元素 <= 最大输入数额
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 将数量为数额数组[0]的路径[0]的token从调用者账户发送到(路径0,路径1)的pair合约地址
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        // 私有交换方法(数额数组，路径数组，to地址)
        _swap(amounts, path, to);
    }

    /**
     * @dev 根据精确的ETH交换尽量多的token,给的是ETH输入  求输出
     * @param amountOutMin 最小输出数额
     * @param path 路径数组
     * @param to to地址
     * @param deadline 最后期限
     * @return amounts[] 数额数组
     */
    function swapExactETHForTokens(
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    )
        external
        override
        payable // payable修饰符，表示可以接收ETH
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        // 确认路径数组第一个元素 == WETH地址
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 数额数组 = 遍历路径数组((精确输入数额*储备量Out) / (储备量In * 1000 + msg.value))
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        // 确认数额数组最后一个元素 >= 最小输出数额
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 将数额数组[0]的数额存款ETH发送到WETH合约
        IWETH(WETH).deposit{value: amounts[0]}();
        // 断言将数额数组[0]的数额的WETH发送到(路径0,路径1)的pair合约地址
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        // 私有交换方法(数额数组，路径数组，to地址)
        _swap(amounts, path, to);
    }

    /**
     * @dev 使用尽量少的token交换精确地ETH，相当于给输出ETH，求输入
     * @param amountOut 精确输出数额
     * @param amountInMax 最大输入数额
     * @param path 路径数组
     * @param to to地址
     * @param deadline 最后期限
     * @return amounts[] 数额数组
     */
    function swapTokensForExactETH(uint256 amountOut, uint256 amountInMax, address[] calldata path, address to, uint256 deadline)
        external
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        // 确认路径数组最后一个地址元素 == WETH地址
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 数额数组 ≈ 遍历路径数组((储备量In*储备量Out * 1000) / (储备量Out - 输出数额*997)+1)
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 确认数额数组第一个元素 <= 最大输入数额
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 将数量为数额数组[0]的路径[0]的token从调用者账户发送到(路径0,路径1)的pair合约地址
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        // 私有交换方法(数额数组，路径数组，当前合约地址)
        _swap(amounts, path, address(this));
        // 从WETH合约 提款 数额数组最后一个数值的ETH
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        // 将数额数组最后一个数值的ETH发送到to地址
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    /**
     * @dev 根据精确的token交换尽量多的ETH（给的是token输入，求输出，输出是ETH）
     * @param amountIn 精确输入数额
     * @param amountOutMin 最小输出数额
     * @param path 路径数组
     * @param to to地址
     * @param deadline 最后期限
     * @return amount[] 数额数组
     */
    function swapExactTokensForETH(
        uint256 amountIn, 
        uint256 amountOutMin, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    )
        external
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        // 确认路径数组最后一个地址元素 == WETH地址
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 数额数组 = 遍历路径数组((精确输入数额*储备量Out) / (储备量In * 1000 + 输入数额))
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        // 确认数额数组最后一个元素 >= 最小输出数额
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        // 将数量为数额数组[0]的路径[0]的token从调用者账户发送到(路径0,路径1)的pair合约地址
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        // 私有交换方法(数额数组，路径数组，当前合约地址)
        _swap(amounts, path, address(this));
        // 从WETH合约 提款 数额数组最后一个数值的ETH
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        // 将数额数组最后一个数值的ETH发送到to地址
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    /**
     * @dev 使用尽量少的token交换精确的token，相当于给输出（精确的token），求输入（输入是ETH）
     * @param amountOut 精确输出数额
     * @param path 路径数组
     * @param to to地址
     * @param deadline 最后期限
     * @return amounts[] 数额数组
     */
    function swapETHForExactTokens(
        uint256 amountOut, 
        address[] calldata path, 
        address to, 
        uint256 deadline
    )
        external
        override
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        // 确认路径数组第一个元素 == WETH地址
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        // 数额数组 ≈ 遍历路径数组((储备量In*储备量Out * 1000) / (储备量Out - 输出数额*997)+1)
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        // 确认数额数组第一个元素 <= msg.value
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        // 将数额数组[0]的数额存款ETH发送到WETH合约
        IWETH(WETH).deposit{value: amounts[0]}();
        // 断言将数额数组[0]的数额的WETH发送到(路径0,路径1)的pair合约地址
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        // 私有交换方法(数额数组，路径数组，to地址)
        _swap(amounts, path, to);
        // 如果‘收到的主币数量’ > ‘数额数组[0]’，则返还‘收到的主币数量’ - ‘数额数组[0]’
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]); // refund dust eth, if any
    }

    // 后面的几个相当于是将Library里面的方法进行一个对外暴露的重写
    function quote(
        uint256 amountA, 
        uint256 reserveA, 
        uint256 reserveB
    ) public pure override returns (uint256 amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    // ****Library Functions ****
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure override returns (uint256 amountOut) {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) public pure override returns (uint256 amountIn) {
        return UniswapV2Library.getAmountOut(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) public view override returns (uint256[] memory amounts) {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view override returns (uint256[] memory amounts) {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}